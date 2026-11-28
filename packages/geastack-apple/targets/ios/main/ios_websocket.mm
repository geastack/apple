// Compile the common Apple WebSocket provider in this translation unit so
// binary sends share its live URLSession, admission checks and queue accounting.
#include "host/websocket_apple.mm"

extern "C" bool gea_ios_websocket_send_binary_base64(const gea::host::WebSocket &socket, const std::string &base64) {
  using namespace gea::host::websocket;
  const auto state = apple::find(socket.nativeHandle);
  if (!state) return false;
  NSString *encoded = [[NSString alloc] initWithBytes:base64.data() length:base64.size() encoding:NSUTF8StringEncoding];
  NSData *data = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
  if (!data.length) return false;

  NSURLSessionWebSocketTask *task;
  {
    std::lock_guard lock(state->mutex);
    if (state->stopped || !state->opened || state->sending || data.length > apple::maxBuffered - state->bytes) return false;
    task = state->task;
    state->bytes += data.length;
  }

  const auto size = data.length;
  std::weak_ptr<apple::State> weak = state;
  [task sendMessage:[[NSURLSessionWebSocketMessage alloc] initWithData:data] completionHandler:^(NSError *error) {
    if (auto current = weak.lock()) {
      if (error) {
        current->failed("WebSocket binary send failed");
        return;
      }
      std::lock_guard lock(current->mutex);
      if (!current->stopped) current->bytes -= size;
    }
  }];
  return true;
}
