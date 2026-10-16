import {runNativeTest} from './native-harness.mjs'
if(process.platform!=='darwin')process.exit(0)
// Hidden-window test mode: no activation, no visible window, no audio.
await runNativeTest('root-input-retirement-test',{test:new URL('./root-input-retirement.mm',import.meta.url).pathname,sources:['macos_renderer.mm','canvas_view.mm','press_bridge.mm','image_bridge.mm','color_convert.mm','font_registry.mm','macos_timers.mm','macos_display.mm','macos_sensors.cpp','macos_memory.cpp'],frameworks:['QuartzCore','CoreImage'],env:{GEA_MACOS_BACKGROUND_TEST:'1',GEA_AUDIO_DISABLED:'1'}})
