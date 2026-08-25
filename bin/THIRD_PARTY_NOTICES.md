# Third-party notices

Swag itself is distributed under the repository-level `LICENCE`. Files derived from third-party
work carry compact `@LICENCE`, `@ORIGIN`, `@MODIFIED`, and `@NOTICE` metadata beside the code.
This file preserves the corresponding attribution and licence text in one place.

`NOASSERTION` means that the upstream source does not state redistribution terms. It is an
explicit review finding, not a licence grant.

## Scoped notices and fixture licences

Some redistributions are documented closer to the files they cover:

- `std/modules/audio/THIRD_PARTY_NOTICES.md`: clean-room comparison sources for the native audio
  decoders.
- `apps/modules/sVaultDrive/THIRD-PARTY-NOTICES.md`: WinFsp and the other sVaultDrive
  dependencies.
- `std/modules/gui/src/theme/icons.license.txt`: GUI icon sources.
- `std/modules/gui/src/tests/datas/pdf-fixture-license-apache-2.0.txt` and
  `pdf-fixture-license-llvm.txt`: PDF test fixtures.
- `std/modules/pixel/src/tests/datas/svg-wpt.license.md`: SVG Web Platform Tests fixtures.
- `std/modules/video/src/tests/datas/LICENSE.bsd-2-clause.txt`: video test fixture.

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

## Game Programming Gems smooth damping

- Licence: NOASSERTION
- Origin: *Game Programming Gems 4*, chapter 1.10.
- Used by: `Math.smoothDamp` in Core.
- The existing source attribution does not identify a code archive or redistribution licence.
  Provenance must be clarified or the implementation independently replaced before it can be
  described as fully cleared.

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

## Pacman example

- Licence: BSD-3-Clause
- Copyright: Copyright (c) 2017 Alex Macpherson. All rights reserved.
- Origin: <https://github.com/alexjamesmacpherson/pacman>
- The Swag port and its redistributed data files are modified from the upstream project.

## Invaders example assets

- Example inspiration and asset bundle: <https://github.com/clear-code-projects/Space-invaders>
- `music.wav`: CC-BY-SA-3.0, by wyver9, from
  <https://opengameart.org/content/arcade-boss-tracks-8-bitchiptune>.
- `explosion.wav` and `laser.wav`: CC0-1.0, by SubspaceAudio, from
  <https://opengameart.org/content/512-sound-effects-8-bit-style>.
- `Pixeled.ttf`: LicenseRef-Pixeled-Freeware, by OmegaPC777; the distributor describes it as
  "100% Free" at <https://www.dafont.com/pixeled.font> but supplies no SPDX licence text.
- `extra.png`, `green.png`, `player.png`, `red.png`, `tv.png`, and `yellow.png`: NOASSERTION.
  The tutorial repository says that its publisher created the graphics but provides no licence.

The Invaders graphics therefore still require either permission from their author or replacement
before a redistribution can be described as fully cleared.

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
