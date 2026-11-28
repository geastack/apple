// SPDX-License-Identifier: Apache-2.0
#import <CFNetwork/CFNetwork.h>
#import <Foundation/Foundation.h>
#import <Network/Network.h>

#include "host/http.h"

#include <charconv>
#include <memory>
#include <unordered_map>

namespace gea::host::http {
namespace {
constexpr size_t maxHeader = 16 * 1024;
constexpr size_t maxBody = 1024 * 1024;
constexpr size_t maxFile = 4 * 1024 * 1024;
std::unordered_map<NativeHttpServerHandle, nw_listener_t> listeners;
size_t activeConnections = 0;

std::string utf8(NSString *value) { return value.UTF8String ?: ""; }

NSString *ns(const std::string &value) {
  return [[NSString alloc] initWithBytes:value.data() length:value.size() encoding:NSUTF8StringEncoding];
}

struct Connection {
  explicit Connection(nw_connection_t socket, NativeHttpServerHandle server) : socket(socket), server(server) {}
  ~Connection() { if (message) CFRelease(message); }
  nw_connection_t socket;
  NativeHttpServerHandle server;
  CFHTTPMessageRef message = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, true);
  size_t received = 0;
  bool done = false;
};

void close(const std::shared_ptr<Connection> &client) {
  if (client->done) return;
  client->done = true;
  CFRelease(client->message);
  client->message = nullptr;
  --activeConnections;
  nw_connection_cancel(client->socket);
}

void respond(std::shared_ptr<Connection> client, HttpReply reply) {
  if (client->done) return;
  NSData *body = nil;
  if (!reply.file.empty()) {
    NSString *path = ns(reply.file);
    NSNumber *size = [[NSFileManager.defaultManager attributesOfItemAtPath:path error:NULL] objectForKey:NSFileSize];
    if (size && size.unsignedLongLongValue <= maxFile) body = [NSData dataWithContentsOfFile:path];
    if (!body) {
      reply.status = 404;
      reply.contentType = "text/plain";
      reply.body = "File not found";
    }
  }
  if (!body) body = [NSData dataWithBytes:reply.body.data() length:reply.body.size()];
  CFHTTPMessageRef response = CFHTTPMessageCreateResponse(kCFAllocatorDefault, reply.status, nullptr, kCFHTTPVersion1_1);
  for (const auto &header : reply.headers) {
    CFHTTPMessageSetHeaderFieldValue(response, (__bridge CFStringRef)ns(header.name), (__bridge CFStringRef)ns(header.value));
  }
  CFHTTPMessageSetHeaderFieldValue(response, CFSTR("Content-Type"), (__bridge CFStringRef)ns(reply.contentType));
  CFHTTPMessageSetHeaderFieldValue(response, CFSTR("Content-Length"), (__bridge CFStringRef)[@(body.length) stringValue]);
  CFHTTPMessageSetHeaderFieldValue(response, CFSTR("Connection"), CFSTR("close"));
  CFHTTPMessageSetBody(response, (__bridge CFDataRef)body);
  NSData *packet = CFBridgingRelease(CFHTTPMessageCopySerializedMessage(response));
  CFRelease(response);
  auto bytes = dispatch_data_create(packet.bytes, packet.length, dispatch_get_main_queue(), ^{
    (void)packet;
  });
  nw_connection_send(client->socket, bytes, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true, ^(nw_error_t) {
    close(client);
  });
}

HttpReply failure(int status, const char *message) {
  HttpReply reply;
  reply.status = status;
  reply.body = message;
  return reply;
}

void receive(std::shared_ptr<Connection> client) {
  nw_connection_receive(client->socket, 1, 8192, ^(dispatch_data_t data, nw_content_context_t, bool complete, nw_error_t error) {
    if (client->done) return;
    if (error || !data) { close(client); return; }
    const void *buffer = nullptr;
    size_t length = 0;
    auto contiguous = dispatch_data_create_map(data, &buffer, &length);
    client->received += length;
    if (client->received > maxHeader + maxBody) {
      respond(client, failure(413, "Request too large"));
      return;
    }
    if (!CFHTTPMessageAppendBytes(client->message, static_cast<const UInt8 *>(buffer), length)) {
      respond(client, failure(400, "Invalid HTTP request"));
      return;
    }
    (void)contiguous;
    if (!CFHTTPMessageIsHeaderComplete(client->message)) {
      if (client->received > maxHeader || complete) respond(client, failure(400, "Invalid HTTP headers"));
      else receive(client);
      return;
    }
    NSDictionary<NSString *, NSString *> *fields = CFBridgingRelease(CFHTTPMessageCopyAllHeaderFields(client->message));
    auto header = [&](NSString *name) -> std::string {
      NSString *value = CFBridgingRelease(CFHTTPMessageCopyHeaderFieldValue(client->message, (__bridge CFStringRef)name));
      return utf8(value);
    };
    if (!header(@"Transfer-Encoding").empty()) {
      respond(client, failure(400, "Transfer encoding is not supported"));
      return;
    }
    size_t expected = 0;
    const std::string size = header(@"Content-Length");
    if (!size.empty()) {
      const auto result = std::from_chars(size.data(), size.data() + size.size(), expected);
      if (result.ec != std::errc() || result.ptr != size.data() + size.size() || expected > maxBody) {
        respond(client, failure(413, "Invalid request size"));
        return;
      }
    }
    NSData *body = CFBridgingRelease(CFHTTPMessageCopyBody(client->message));
    if (body.length < expected) {
      if (complete) respond(client, failure(400, "Incomplete request"));
      else receive(client);
      return;
    }
    HttpRequest request;
    NSURL *url = CFBridgingRelease(CFHTTPMessageCopyRequestURL(client->message));
    request.method = utf8(CFBridgingRelease(CFHTTPMessageCopyRequestMethod(client->message)));
    request.path = utf8(url.path);
    request.query = utf8(url.query);
    for (NSString *name in fields) request.headers.push_back({utf8(name), utf8(fields[name])});
    if (expected) {
      const auto *first = static_cast<const uint8_t *>(body.bytes);
      request.body.assign(first, first + expected);
    }
    auto &table = handlerTable();
    const auto entry = table.find(client->server);
    if (entry == table.end() || !entry->second) { respond(client, failure(404, "Server stopped")); return; }
    const RequestHandler handler = entry->second;
    try {
      respond(client, handler(request));
    } catch (...) {
      respond(client, failure(500, "Request failed"));
    }
  });
}
} // namespace

bool platform_listen(NativeHttpServerHandle handle, int port) {
  if (port < 1 || port > 65535 || listeners.contains(handle)) return false;
  auto params = nw_parameters_create_secure_tcp(NW_PARAMETERS_DISABLE_PROTOCOL, NW_PARAMETERS_DEFAULT_CONFIGURATION);
  auto listener = nw_listener_create_with_port(std::to_string(port).c_str(), params);
  if (!listener) return false;
  listeners.emplace(handle, listener);
  nw_listener_set_queue(listener, dispatch_get_main_queue());
  nw_listener_set_new_connection_handler(listener, ^(nw_connection_t socket) {
    if (activeConnections >= 12) { nw_connection_cancel(socket); return; }
    ++activeConnections;
    auto client = std::make_shared<Connection>(socket, handle);
    nw_connection_set_queue(socket, dispatch_get_main_queue());
    nw_connection_start(socket);
    receive(client);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
      close(client);
    });
  });
  nw_listener_start(listener);
  return true;
}

void platform_close(NativeHttpServerHandle handle) {
  const auto listener = listeners.find(handle);
  if (listener == listeners.end()) return;
  nw_listener_cancel(listener->second);
  listeners.erase(listener);
}
} // namespace gea::host::http
