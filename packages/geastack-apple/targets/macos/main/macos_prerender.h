// SPDX-License-Identifier: Apache-2.0
#pragma once

@class NSString;

bool gea_macos_prepare_prerender(int width, int height);
bool gea_macos_write_prerender_png(NSString *path);
void gea_macos_set_prerender_time(int timestampMs);
