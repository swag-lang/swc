# RealVideo decoder notices

## FFmpeg RealVideo decoder

The slice syntax, entropy tables, transforms, prediction, motion compensation, and loop filter in this
directory are adapted from FFmpeg n7.1's `libavcodec/rv34.c`, `rv40.c`, `rv34data.h`,
`rv34vlc.h`, `rv40data.h`, `rv40vlc2.h`, `rv34dsp.c`, `rv40dsp.c`, `h264pred.c`, and
`h264pred_template.c`.

- Origin: <https://github.com/FFmpeg/FFmpeg/tree/n7.1/libavcodec>
- Copyright (c) 2007 Mike Melanson, Konstantin Shishkov.
- Copyright (c) 2008 Konstantin Shishkov.
- Copyright (c) 2011 Janne Grunau.
- H.264 prediction copyright (c) 2003 Michael Niedermayer and contributors.
- Licence: GNU Lesser General Public License, version 2.1 or, at your option, any later version.
- Modifications (2026-10-27): reimplemented in Swag with owned picture buffers, bounded bit reading,
  scalar reconstruction, and the video module's streaming and seeking interface. The code
  length tables are stored as binary decoding trees.

The licence text is in `COPYING.LGPLv2.1`. These adapted files remain under those terms.
They are provided without warranty, including the implied warranties of merchantability or
fitness for a particular purpose. No FFmpeg library is linked or loaded at runtime.
