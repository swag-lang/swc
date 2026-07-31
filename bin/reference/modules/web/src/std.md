# Standard library

The standard workspace lives under `bin/std` beside the compiler. Its modules
are built from the same revision as `swc`, and their generated API pages link
back to the maintained declarations and comments in
[`bin/std/modules`](https://github.com/swag-lang/swc/tree/master/bin/std/modules).

Import a standard module from `module.swg` or a script setup section:

```swag
#import("core", location: "swag@std")
```

The `swag@std` location is resolved through `SWAG_PATH`, which must point to the
compiler's `bin` directory.

## Application libraries

| Module | Namespace | Purpose |
|---|---|---|
| [std.core](std.core.html) | `Core` | Collections, strings, files, paths, serialization, math, time, concurrency, diagnostics, input, and host services |
| [std.pixel](std.pixel.html) | `Pixel` | Images, codecs, transforms, vector drawing, text layout, brushes, paths, and OpenGL rendering |
| [std.gui](std.gui.html) | `Gui` | Native desktop applications, surfaces, controls, layouts, events, themes, dialogs, and actions |
| [std.audio](std.audio.html) | `Audio` | WAV loading, decoding, streaming, voices, buses, codecs, and process-wide playback |
| [std.truetype](std.truetype.html) | `TrueType` | TrueType parsing, metrics, outlines, rasterization, kerning, and distance fields |

These modules expose Swag-owned abstractions and task-oriented guides in
addition to symbol reference entries. Follow their ownership and lifetime
rules: containers and images own storage, while slices, string views, glyph
slots, and several drawing inputs borrow it.

## Native bindings

| Module | Namespace | Upstream surface |
|---|---|---|
| [std.ogl](std.ogl.html) | `Ogl` | OpenGL declarations and Windows context integration |
| [std.win32](std.win32.html) | `Win32` | Windows SDK declarations used by the standard workspace |
| [std.gdi32](std.gdi32.html) | `Gdi32` | Windows GDI declarations |
| [std.gdiplus](std.gdiplus.html) | `Gdiplus` | Windows GDI+ flat API declarations |
| [std.xinput](std.xinput.html) | `XInput` | Microsoft XInput declarations |
| [std.xaudio2](std.xaudio2.html) | `XAudio2` | Microsoft XAudio2 declarations and COM-style interfaces |

Binding pages are searchable declaration indices, not replacements for the
upstream Microsoft or Khronos specifications. They document Swag-specific
helpers and deviations, while names, flags, structures, and native functions
retain their upstream contracts.

## Platform and build model

The current standard workspace targets Windows x86-64. High-level modules pull
their dependencies transitively: for example, `gui` imports `pixel`, and
`pixel` imports `core`, `ogl`, and `truetype`. Import the module your code uses
directly; do not depend on a transitive import remaining part of another
module's implementation.

Standard modules build as shared libraries unless their setup selects an export
binding. Workspace output and exported APIs are grouped by backend kind, build
configuration, and architecture under `bin/std/.output`.
