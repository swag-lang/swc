# Standard library

The standard workspace lives under `bin/std` beside the compiler. Its sources
are compiled into each application, and the documentation links
back to the maintained declarations and comments in
[`bin/std/modules`](https://github.com/swag-lang/swc/tree/master/bin/std/modules).

Import a standard module from `module.swg` or a script setup section:

```swag
#import("core", location: "swag@std")
```

`swag@std` is the standard library beside the compiler that runs the build.
`SWAG_PATH` answers instead for a compiler installed without one, and points to
that library's `bin` directory.

## Application namespaces

| Module | Namespace | Purpose |
|---|---|---|
| [std.core](std.core.html) | `Core` | Collections, strings, files, paths, serialization, math, time, concurrency, diagnostics, input, and host services |
| [std.pixel](std.pixel.html) | `Pixel` | Images, codecs, transforms, vector drawing, text layout, brushes, paths, and OpenGL rendering |
| [std.gui](std.gui.html) | `Gui`, `Pdf` | Native desktop applications, surfaces, controls, layouts, events, themes, dialogs, document engines, and actions |
| [std.audio](std.audio.html) | `Audio` | WAV loading, decoding, streaming, voices, buses, codecs, and process-wide playback |
| [std.video](std.video.html) | `Video` | Streamed video reading and writing, frame by frame, with YUV4MPEG2 and Motion JPEG AVI codecs |
| [std.truetype](std.truetype.html) | `TrueType` | TrueType parsing, metrics, outlines, rasterization, kerning, and distance fields |

These modules expose Swag-owned abstractions and task-oriented guides in
addition to symbol reference entries. Follow their ownership and lifetime
rules: containers and images own storage, while slices, string views, glyph
slots, and several drawing inputs borrow it.

## Native bindings

| Module | Namespace | Upstream surface |
|---|---|---|
| [std.ogl](std.ogl.html) | `Ogl` | OpenGL declarations and Windows context integration |
| [std.win32](std.win32.html) | `Win32`, `Win32.Gdi32`, `Win32.Gdiplus`, `Win32.XInput` | Windows SDK, GDI, GDI+, and XInput declarations |

Binding pages are searchable declaration indices, not replacements for the
upstream Microsoft or Khronos specifications. The Windows APIs share one page,
with their upstream-specific namespaces intact. Names, flags, structures, and
native functions retain their upstream contracts.

## Platform and build model

The standard workspace supports Windows and Linux on x86-64. High-level source groups pull
their dependencies transitively: for example, `gui` imports `pixel`, and
`pixel` imports `core`, `ogl`, and `truetype`. Import the module your code uses
directly; do not depend on a transitive import remaining part of another
module's implementation.

The compiler compiles each imported source group once per application. All
groups share its build configuration and runtime.
