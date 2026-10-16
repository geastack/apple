#pragma once
#import <AppKit/AppKit.h>
#include "events.h"

// NSEvent.keyCode is a physical AppKit scan code, not a legacy keyCode.
// `key` follows the current layout; `code` names the physical position.
static const char *geaPhysicalKeyCode(unsigned short code) {
 switch(code) {
  case 0:return "KeyA";case 1:return "KeyS";case 2:return "KeyD";case 3:return "KeyF";
  case 4:return "KeyH";case 5:return "KeyG";case 6:return "KeyZ";case 7:return "KeyX";
  case 8:return "KeyC";case 9:return "KeyV";case 11:return "KeyB";case 12:return "KeyQ";
  case 13:return "KeyW";case 14:return "KeyE";case 15:return "KeyR";case 16:return "KeyY";
  case 17:return "KeyT";case 18:return "Digit1";case 19:return "Digit2";case 20:return "Digit3";
  case 21:return "Digit4";case 22:return "Digit6";case 23:return "Digit5";case 24:return "Equal";
  case 25:return "Digit9";case 26:return "Digit7";case 27:return "Minus";case 28:return "Digit8";
  case 29:return "Digit0";case 30:return "BracketRight";case 31:return "KeyO";case 32:return "KeyU";
  case 33:return "BracketLeft";case 34:return "KeyI";case 35:return "KeyP";case 36:return "Enter";
  case 37:return "KeyL";case 38:return "KeyJ";case 39:return "Quote";case 40:return "KeyK";
  case 41:return "Semicolon";case 42:return "Backslash";case 43:return "Comma";case 44:return "Slash";
  case 45:return "KeyN";case 46:return "KeyM";case 47:return "Period";case 48:return "Tab";
  case 49:return "Space";case 50:return "Backquote";case 51:return "Backspace";case 53:return "Escape";
  case 54:return "MetaRight";case 55:return "MetaLeft";case 56:return "ShiftLeft";case 57:return "CapsLock";
  case 58:return "AltLeft";case 59:return "ControlLeft";case 60:return "ShiftRight";
  case 61:return "AltRight";case 62:return "ControlRight";case 63:return "Fn";
  case 65:return "NumpadDecimal";case 67:return "NumpadMultiply";case 69:return "NumpadAdd";
  case 71:return "NumLock";case 75:return "NumpadDivide";case 76:return "NumpadEnter";
  case 78:return "NumpadSubtract";case 81:return "NumpadEqual";case 82:return "Numpad0";
  case 83:return "Numpad1";case 84:return "Numpad2";case 85:return "Numpad3";case 86:return "Numpad4";
  case 87:return "Numpad5";case 88:return "Numpad6";case 89:return "Numpad7";case 91:return "Numpad8";
  case 92:return "Numpad9";case 96:return "F5";case 97:return "F6";case 98:return "F7";
  case 99:return "F3";case 100:return "F8";case 101:return "F9";case 103:return "F11";
  case 109:return "F10";case 111:return "F12";case 115:return "Home";case 116:return "PageUp";
  case 117:return "Delete";case 118:return "F4";case 119:return "End";case 120:return "F2";
  case 121:return "PageDown";case 122:return "F1";case 123:return "ArrowLeft";
  case 124:return "ArrowRight";case 125:return "ArrowDown";case 126:return "ArrowUp";
  default:return "Unidentified";
 }
}
static gea::framework::events::PointerEvent geaNativeKey(NSEvent *native, bool composing, bool up) {
 gea::framework::events::PointerEvent event;
 event.type=up?gea::framework::events::PointerEventType::KeyUp:gea::framework::events::PointerEventType::KeyDown;
 event.code=geaPhysicalKeyCode(native.keyCode);
 NSString *characters=(native.modifierFlags & (NSEventModifierFlagCommand|NSEventModifierFlagControl))?
  native.charactersIgnoringModifiers:native.characters;
 event.key=characters.UTF8String?:"";
 switch(native.keyCode) {
  case 36:case 76:event.key="Enter";event.keyCode=13;break;
  case 48:event.key="Tab";event.keyCode=9;break;
  case 49:event.key=" ";event.keyCode=32;break;
  case 51:event.key="Backspace";event.keyCode=8;break;
  case 53:event.key="Escape";event.keyCode=27;break;
  case 115:event.key="Home";event.keyCode=36;break;
  case 116:event.key="PageUp";event.keyCode=33;break;
  case 117:event.key="Delete";event.keyCode=46;break;
  case 119:event.key="End";event.keyCode=35;break;
  case 121:event.key="PageDown";event.keyCode=34;break;
  case 123:event.key="ArrowLeft";event.keyCode=37;break;
  case 124:event.key="ArrowRight";event.keyCode=39;break;
  case 125:event.key="ArrowDown";event.keyCode=40;break;
  case 126:event.key="ArrowUp";event.keyCode=38;break;
  default: {
   NSString *upper=[native.charactersIgnoringModifiers uppercaseString];
   if(upper.length==1)event.keyCode=[upper characterAtIndex:0];
   break;
  }
 }
 event.altKey=(native.modifierFlags & NSEventModifierFlagOption)!=0;
 event.ctrlKey=(native.modifierFlags & NSEventModifierFlagControl)!=0;
 event.metaKey=(native.modifierFlags & NSEventModifierFlagCommand)!=0;
 event.shiftKey=(native.modifierFlags & NSEventModifierFlagShift)!=0;
 event.repeat=native.isARepeat;event.isComposing=composing;
 return event;
}
