#pragma once

#include <cstdint>

namespace gea::macos::thermalright {

bool enabled();
int width();
int height();
int fps();
bool submitRgb565(const std::uint16_t *pixels, int width, int height);
void shutdown();

} // namespace gea::macos::thermalright
