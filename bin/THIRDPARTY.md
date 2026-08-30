# Third-party notices

Swag itself is distributed under the repository-level `LICENCE`. The Swag Vault application is
separately distributed under the GPL terms in `apps/modules/swagvault/LICENCE.md`; neither licence
is a third-party notice. Files derived from third-party work carry compact `@LICENCE`, `@ORIGIN`,
`@MODIFIED`, and `@NOTICE` metadata beside the code. This file preserves the corresponding
attribution and licence text in one place.

## Scoped notices and fixture licences

Some redistributions are documented closer to the files they cover:

- `apps/modules/swagscope/src/tests/datas/THIRDPARTY.md`: media viewer test fixtures.
- `apps/modules/swagvault/THIRDPARTY.md`: WinFsp and the other Swag Vault dependencies.
- `std/modules/audio/src/tests/datas/THIRDPARTY.md`: audio test fixtures.
- `std/modules/audio/src/codec/dts/THIRDPARTY.md`: FFmpeg's DTS ADPCM predictor codebook.
- `std/modules/gui/src/theme/THIRDPARTY.md`: GUI icon sources.
- `std/modules/gui/src/tests/datas/THIRDPARTY.md`: HTML and PDF test fixtures.
- `std/modules/pixel/src/tests/datas/THIRDPARTY.md`: SVG Web Platform Tests fixtures.
- `std/modules/video/src/tests/datas/THIRDPARTY.md`: video test fixtures.

## Go standard library

- Licence: BSD-3-Clause
- Copyright: Copyright 2009 The Go Authors.
- Origin: <https://github.com/golang/go>
- Used by: integer arithmetic, UTF-8 and Unicode tables, and string/float conversions in Core.

## Go x-image

- Licence: BSD-3-Clause
- Copyright: Copyright 2009 The Go Authors.
- Origin: <https://github.com/golang/image>
- Used by: the VP8 and VP8L WebP decoders.

## Odin

- Licence: Zlib
- Copyright: Copyright (c) 2016-2025 Ginger Bill. All rights reserved.
- Origin: <https://github.com/odin-lang/Odin>
- Used by: the Zlib inflater and part of the PNG decoder.

## miniz

- Licence: MIT
- Copyright: Copyright 2013-2014 RAD Game Tools and Valve Software.
- Copyright: Copyright 2010-2014 Rich Geldreich and Tenacious Software LLC.
- Origin: <https://github.com/richgel999/miniz>
- Used by: the Deflate encoder.

## FastNoise

- Licence: MIT
- Copyright: Copyright (c) 2020 Jordan Peck and contributors.
- Origin: <https://github.com/Auburn/FastNoiseLite>
- Used by: the FastNoise Legacy and FastNoiseLite ports in Core.

## MT19937-64

- Licence: BSD-3-Clause
- Copyright: Copyright (C) 2004 Makoto Matsumoto and Takuji Nishimura.
- Origin: <https://github.com/mattgallagher/CwlUtils/blob/master/Sources/ReferenceRandomGenerators/mt19937-64.c>
- Used by: the 64-bit Mersenne Twister implementation in Core.

## CityHash

- Licence: MIT
- Copyright: Copyright (c) 2011 Google, Inc.
- Authors: Geoff Pike and Jyrki Alakuijala.
- Origin: <https://github.com/google/cityhash>
- Used by: CityHash32 in Core.

## Jenkins hash

- Licence: LicenseRef-Public-Domain
- Author: Bob Jenkins.
- Origin: <https://burtleburtle.net/bob/hash/integer.html>
- Upstream states that the integer hash is public domain.

## MurmurHash3

- Licence: LicenseRef-Public-Domain
- Author: Austin Appleby.
- Origin: <https://github.com/aappleby/smhasher/blob/master/src/MurmurHash3.cpp>
- Upstream places MurmurHash3 in the public domain and disclaims copyright.

## Natural sort

- Licence: Zlib
- Copyright: Copyright (C) 2000, 2004 Martin Pool.
- Origin: <https://github.com/sourcefrog/natsort>
- Used by: Latin-1 natural string comparison in Core.

## Poly2Tri

- Licence: BSD-3-Clause
- Copyright: Copyright (c) 2009-2018 Poly2Tri Contributors.
- Origin: <https://github.com/jhasse/poly2tri>

## Clipper

- Licence: BSL-1.0
- Author: Angus Johnson.
- Origin: <https://www.angusj.com/clipper2/Docs/Overview.htm>
- Used by: polygon clipping and offsetting in Pixel.

## Geometric Tools

- Licence: BSL-1.0
- Copyright: Copyright (c) 1998-2022 David Eberly, Geometric Tools.
- Origin: <https://www.geometrictools.com/GTE/Mathematics/DistSegmentSegment.h>
- Used by: closest-point computation between two line segments in Core.

## libspng

- Licence: BSD-2-Clause
- Copyright: Copyright (c) 2018-2023 Randy. All rights reserved.
- Origin: <https://github.com/randy408/libspng>
- Used by: PNG filtering, sample conversion, scanline traversal, and encoding in Pixel.

## gifdec

- Licence: LicenseRef-Public-Domain
- Origin: <https://github.com/lecram/gifdec>
- Upstream releases all gifdec source code and documentation into the public domain without
  warranty.

## MPEG-4 Part 2 normative tables

- Licence: MIT
- Copyright: Copyright (c) 2026 Karpeles Lab Inc.
- Origin: <https://github.com/OxideAV/oxideav-mpeg4video>
- Used by: the Part 2 tables in `std/modules/video/src/decode/mpeg4/tables.swg`.

The tables themselves are the normative content of ISO/IEC 14496-2 - the macroblock type, coded
block pattern, motion vector, direct-current size and coefficient code tables of Annex B, the scan
orders, and the default quantiser matrices - and are facts of the format rather than that project's
expression of them. They were recovered from its transcription of the standard and rewritten in the
form this decoder reads. Every one was then re-checked here: each is prefix-free, no Kraft sum
exceeds one, each coefficient table names 102 distinct events, the motion vector table covers minus
thirty-two to thirty-two without a hole, and each scan order is a permutation of the sixty-four
positions. `mpeg4.tables.test.swg` re-checks all of that inside this repository. No source line of
that project is reproduced here.

## MP3 normative tables

- Licence: CC0-1.0 (minimp3) and the Unlicence (PDMP3)
- Copyright: both projects are dedicated to the public domain by their authors.
- Origin: <https://github.com/lieff/minimp3> and <https://github.com/technosaurus/PDMP3>
- Used by: the Layer III tables in `std/modules/audio/src/codec/mp3/tables.swg`.

The tables themselves are the normative content of ISO/IEC 11172-3 and 13818-3 — Huffman code
tables, scalefactor band widths, and the synthesis window — and are facts of the format rather
than either project's expression of them. Both projects store them in their own packed decoding
structures; those were unpacked, compared code by code against each other, and written out in the
form the standard prints. The 1,298 Huffman code words agree between the two sources, every table
is a complete prefix code, and `mp3.tables.test.swg` re-checks that inside this repository. No
source line of either project is reproduced here.

## Pacman example

- Licence: BSD-3-Clause
- Copyright: Copyright (c) 2017 Alex Macpherson. All rights reserved.
- Origin: <https://github.com/alexjamesmacpherson/pacman>
- The Swag port and its redistributed data files are modified from the upstream project.

## Invaders example audio

The example code and vector artwork were written for Swag. Its game structure acknowledges the
Clear Code [Space Invaders tutorial](https://github.com/clear-code-projects/Space-invaders);
no source code, graphics, or fonts from that repository are redistributed.

- `music.wav`: CC-BY-SA-3.0, by wyver9, from
  <https://opengameart.org/content/arcade-boss-tracks-8-bitchiptune>.
- `explosion.wav` and `laser.wav`: CC0-1.0, by SubspaceAudio, from
  <https://opengameart.org/content/512-sound-effects-8-bit-style>.

## Licence texts

### BSD-3-Clause

Redistribution and use in source and binary forms, with or without modification, are permitted
provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of
   conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice, this list of
   conditions and the following disclaimer in the documentation and/or other materials provided
   with the distribution.
3. Neither the name of the copyright holder nor the names of its contributors may be used to
   endorse or promote products derived from this software without specific prior written
   permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER
IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT
OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

### BSD-2-Clause

Redistribution and use in source and binary forms, with or without modification, are permitted
provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of
   conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice, this list of
   conditions and the following disclaimer in the documentation and/or other materials provided
   with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER
IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT
OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

### MIT

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute,
sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or
substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT
OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

### Zlib

This software is provided 'as-is', without any express or implied warranty. In no event will the
authors be held liable for any damages arising from the use of this software.

Permission is granted to anyone to use this software for any purpose, including commercial
applications, and to alter it and redistribute it freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not claim that you wrote the
   original software. If you use this software in a product, an acknowledgment in the product
   documentation would be appreciated but is not required.
2. Altered source versions must be plainly marked as such, and must not be misrepresented as being
   the original software.
3. This notice may not be removed or altered from any source distribution.

### BSL-1.0

Permission is hereby granted, free of charge, to any person or organization obtaining a copy of
the software and accompanying documentation covered by this license (the "Software") to use,
reproduce, display, distribute, execute, and transmit the Software, and to prepare derivative
works of the Software, and to permit third parties to whom the Software is furnished to do so,
all subject to the following:

The copyright notices in the Software and this entire statement, including the above license
grant, this restriction and the following disclaimer, must be included in all copies of the
Software, in whole or in part, and all derivative works of the Software, unless such copies or
derivative works are solely in the form of machine-executable object code generated by a source
language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE AND
NON-INFRINGEMENT. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE
LIABLE FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
