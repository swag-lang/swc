This is the list of all modules that come with the compiler. As they are always in sync, they are considered as **standard**. They are all part of the same workspace **std**.

You can find that workspace locally in `bin/std`, or [here](https://github.com/swag-lang/swag/tree/master/bin/std) on GitHub.

# Modules

| Module | Purpose |
|---|---|
| [std.core](std.core.html) | Main core module, the base of everything else |
| [std.pixel](std.pixel.html) | Image processing and 2D painting |
| [std.gui](std.gui.html) | User interfaces, windows, and widgets |
| [std.audio](std.audio.html) | Sound decoding and playback |

# Wrappers
Those other modules are just wrappers to external libraries.

| Module | Purpose |
|---|---|
| [std.ogl](std.ogl.html) | OpenGL wrapper |
| [std.truetype](std.truetype.html) | TrueType font wrapper |
| [std.win32](std.win32.html) | Windows SDK wrapper |
| [std.gdi32](std.gdi32.html) | Windows GDI wrapper |
| [std.gdiplus](std.gdiplus.html) | Windows GDI+ wrapper |
| [std.xinput](std.xinput.html) | Microsoft XInput wrapper |
| [std.xaudio2](std.xaudio2.html) | Microsoft XAudio2 wrapper |
