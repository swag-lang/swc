# GUI test fixture sources and licences

## Rustdoc HTML fixture

These files are unmodified copies from the documentation installed by the Rust
1.97.1 toolchain (`rustc 1.97.1 (8bab26f4f 2026-07-14)`). They preserve a real
8.15 MB source page whose single highlighted code block expands to more than
400,000 DOM nodes. That scale is intentional: it protects the HTML viewer from
quadratic selector matching and unbounded paint/hit-test scans which small
fixtures cannot expose.

| Local file | Installed Rust distribution file | SHA-256 |
| --- | --- | --- |
| `html.rustdoc-large.html` | `share/doc/rust/html/src/core/stdarch/crates/core_arch/src/arm_shared/neon/generated.rs.html` | `15445503c601f0b5dd87ad620684f050924d99721085264f2a556fa8b4eac2e5` |
| `html.rustdoc-large.normalize.css` | `share/doc/rust/html/static.files/normalize-9960930a.css` | `42cad0035fb96a13167af4024ed8e0b39a155a2c42140742a3950301ba855e62` |
| `html.rustdoc-large.rustdoc.css` | `share/doc/rust/html/static.files/rustdoc-17e0aaed.css` | `264dc5a58dbfaf73bca6f1b5767413c775d1150c07855f6b399e8672ae3d9597` |
| `html.rustdoc-large.noscript.css` | `share/doc/rust/html/static.files/noscript-f7c3ffd8.css` | `6a2a5f394a2da0eb7d2b7ec97383f47635cb024342a2fadfe159633001bcdf44` |

The Rust Standard Library source and rustdoc assets are distributed under
Apache-2.0 OR MIT; this fixture uses the MIT option. `normalize.css` is also
distributed under MIT. The MIT licence and upstream notices are preserved below.

Copyright in the Rust Standard Library is retained by its contributors,
including The Rust Project Developers. The rustdoc stylesheet is Copyright
2015 The Rust Developers. `normalize.css` is Copyright Nicolas Gallagher and
Jonathan Neal.

### Upstream copyright notices

# REUSE-IgnoreStart

These documentation pages include resources by third parties. This copyright
file applies only to those resources. The following third party resources are
included, and carry their own copyright notices and license terms:

* Fira (FiraSans-Regular.woff2, FiraSans-Medium.woff2,
        FiraMono-Regular.woff2, FiraMono-Medium.woff2):

    Copyright (c) 2014, Mozilla Foundation https://mozilla.org/
    with Reserved Font Name < Fira >.

    Copyright (c) 2014, Telefonica S.A.

    Licensed under the SIL Open Font License, Version 1.1.
    See Fira-LICENSE.txt.

* rustdoc.css, main.js, and playpen.js:

    Copyright 2015 The Rust Developers.
    Licensed under the Apache License, Version 2.0 (see LICENSE-APACHE.txt) or
    the MIT license (LICENSE-MIT.txt) at your option.

* normalize.css:

    Copyright (c) Nicolas Gallagher and Jonathan Neal.
    Licensed under the MIT license (see LICENSE-MIT.txt).

* Source Code Pro (SourceCodePro-Regular.ttf.woff2,
    SourceCodePro-Semibold.ttf.woff2, SourceCodePro-It.ttf.woff2):

    Copyright 2010, 2012 Adobe Systems Incorporated (http://www.adobe.com/),
    with Reserved Font Name 'Source'. All Rights Reserved. Source is a trademark
    of Adobe Systems Incorporated in the United States and/or other countries.

    Licensed under the SIL Open Font License, Version 1.1.
    See SourceCodePro-LICENSE.txt.

* Source Serif 4 (SourceSerif4-Regular.ttf.woff2, SourceSerif4-Bold.ttf.woff2,
    SourceSerif4-It.ttf.woff2, SourceSerif4-Semibold.ttf.woff2):

    Copyright 2014-2021 Adobe (http://www.adobe.com/), with Reserved Font Name
    'Source'. All Rights Reserved. Source is a trademark of Adobe in the United
    States and/or other countries.

    Licensed under the SIL Open Font License, Version 1.1.
    See SourceSerif4-LICENSE.md.

* Nanum Barun Gothic Font (NanumBarunGothic.woff2)

    Copyright 2010, NAVER Corporation (http://www.nhncorp.com)
    with Reserved Font Name Nanum, Naver Nanum, NanumGothic, Naver NanumGothic,
    NanumMyeongjo, Naver NanumMyeongjo, NanumBrush, Naver NanumBrush, NanumPen,
    Naver NanumPen, Naver NanumGothicEco, NanumGothicEco,
    Naver NanumMyeongjoEco, NanumMyeongjoEco, Naver NanumGothicLight,
    NanumGothicLight, NanumBarunGothic, Naver NanumBarunGothic.

    https://hangeul.naver.com/2017/nanum
    https://github.com/hiun/NanumBarunGothic

    Licensed under the SIL Open Font License, Version 1.1.
    See NanumBarunGothic-LICENSE.txt.

* Rust logos (rust-logo.svg, favicon.svg, favicon-32x32.png)

    Copyright 2025 Rust Foundation.
    Licensed under the Creative Commons Attribution license (CC-BY).
    https://rustfoundation.org/policy/rust-trademark-policy/

This copyright file is intended to be distributed with rustdoc output.

# REUSE-IgnoreEnd

### MIT licence

Permission is hereby granted, free of charge, to any
person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the
Software without restriction, including without
limitation the rights to use, copy, modify, merge,
publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software
is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice
shall be included in all copies or substantial portions
of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF
ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED
TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT
SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR
IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.

## PDF fixtures

These files are unmodified copies from Apache PDFBox commit
[`d74ddf04c6a9d8e1fd58a42d90ab7ce2b62a9b8d`](https://github.com/apache/pdfbox/tree/d74ddf04c6a9d8e1fd58a42d90ab7ce2b62a9b8d).
They exercise independent PDF representations instead of round-tripping the Pdf
module's own writer.

| Local file | Upstream file | Coverage | SHA-256 |
| --- | --- | --- | --- |
| `pdfbox-classic-flate.pdf` | [`examples/src/test/resources/org/apache/pdfbox/examples/pdmodel/document.pdf`](https://github.com/apache/pdfbox/blob/d74ddf04c6a9d8e1fd58a42d90ab7ce2b62a9b8d/examples/src/test/resources/org/apache/pdfbox/examples/pdmodel/document.pdf) | PDF 1.4, classic xref table, Flate content stream | `a31f3b5fc79e6ae2703f9d2817af088f29aef4937e370b173512d820a9972c35` |
| `pdfbox-object-stream.pdf` | [`pdfbox-layout-awt/src/test/resources/pdf/HelloWorld.pdf`](https://github.com/apache/pdfbox/blob/d74ddf04c6a9d8e1fd58a42d90ab7ce2b62a9b8d/pdfbox-layout-awt/src/test/resources/pdf/HelloWorld.pdf) | PDF 1.6, xref stream, compressed object stream, embedded font | `7fdc2c96c17d94cd12ee8372d1693c194cfb7f8e9aead0eed761c2e646234624` |
| `pdfbox-jpeg-rgb.pdf` | [`pdfbox/src/test/resources/input/merge/jpegrgb.pdf`](https://github.com/apache/pdfbox/blob/d74ddf04c6a9d8e1fd58a42d90ab7ce2b62a9b8d/pdfbox/src/test/resources/input/merge/jpegrgb.pdf) | DCTDecode RGB image XObject | `e4777c29ec90646d4e3c98f260926050badba2d19dc26f9cff565e47927f2565` |
| `pdfbox-rotation.pdf` | [`pdfbox/src/test/resources/input/rotation.pdf`](https://github.com/apache/pdfbox/blob/d74ddf04c6a9d8e1fd58a42d90ab7ce2b62a9b8d/pdfbox/src/test/resources/input/rotation.pdf) | Inherited page resources and 90-degree rotation | `5087c2afe763d145537d652bb3bc6c321ace3a267b2679ae2c178add3ba7f1d9` |
| `pdfbox-form-xobject.pdf` | [`pdfbox/src/test/resources/input/rendering/tiger-as-form-xobject.pdf`](https://github.com/apache/pdfbox/blob/d74ddf04c6a9d8e1fd58a42d90ab7ce2b62a9b8d/pdfbox/src/test/resources/input/rendering/tiger-as-form-xobject.pdf) | Nested Form XObject and vector paths | `ab356726b3d0bc0e48d0312a4369aa45d21e68d8db2ac2f61f71d99d52eec68f` |

The files are distributed under the Apache License 2.0; see the Apache 2.0 text below.

## LLVM and Polly compatibility corpus

These files are unmodified copies from the LLVM tree at Swag repository commit
[`7328b93084641fe1a86577aefc98c093b26133e5`](https://github.com/swag-lang/swag/tree/7328b93084641fe1a86577aefc98c093b26133e5/llvm).
Together they add 354 real-world pages produced by several generations of PDF tools. They are
distributed under the LLVM Apache 2.0 license with exceptions; see the LLVM licence text below.

| Local file | Upstream file | Pages | SHA-256 |
| --- | --- | ---: | --- |
| `llvm-polly-passes-only.pdf` | `polly/docs/images/LLVM-Passes-only.pdf` | 1 | `0fafd448c03450680f75c5ca7f5974172296a6703b0a013afb9a9cf5b0408ac5` |
| `llvm-polly-passes-late.pdf` | `polly/docs/images/LLVM-Passes-late.pdf` | 1 | `05f1fc2715dc6c02c0e6b6c9ee53b813b8ee92e5cfa2b725a03ca535473546b2` |
| `llvm-polly-passes-early.pdf` | `polly/docs/images/LLVM-Passes-early.pdf` | 1 | `92472cc55f2d3129e815f075614077a19bad58f0965d070fe113e49d12bf8e90` |
| `llvm-polly-passes-all.pdf` | `polly/docs/images/LLVM-Passes-all.pdf` | 1 | `958d4cf63192b511ffaa3ded2e9eb76d35c549b32da6dd262d7a4966eb5b9e48` |
| `llvm-openmp-reference.pdf` | `openmp/runtime/doc/Reference.pdf` | 67 | `bf61427504a7cc96c532c220c9f5ecc58e7c05374617e4e3de21ce987ba2b8e6` |
| `llvm-polly-impact-2011-paper.pdf` | `polly/www/publications/grosser-impact-2011.pdf` | 6 | `1e9c4e9f55f18f088746078109eab63e2027829617e5f2d797532ee6958ad386` |
| `llvm-polly-impact-2011-slides.pdf` | `polly/www/publications/grosser-impact-2011-slides.pdf` | 27 | `9f4bb229ad973fb8a2c0b3124b86e6c604e486cef89e3d01f2d6f81c0c6af125` |
| `llvm-polly-raghesh-masters-thesis.pdf` | `polly/www/publications/raghesh-a-masters-thesis.pdf` | 70 | `f69b6b5a74f07518cfebe7492f176579f758b3e57a8fb6518c37cfa3f66c494c` |
| `llvm-polly-grosser-diploma-thesis.pdf` | `polly/www/publications/grosser-diploma-thesis.pdf` | 101 | `bacd25c4649d5091ec9adbae1dd3c9ac22fe294b029d10f5ac93df5c1d45675f` |
| `llvm-polly-kernelgen-pavt-2012-slides.pdf` | `polly/www/publications/kernelgen-pavt-2012-slides.pdf` | 51 | `307eb68c37983289d849b1ff59744732443974fec1a3a2e4149afbac9a39622f` |
| `llvm-polly-kernelgen-ncar-2012-slides.pdf` | `polly/www/publications/kernelgen-ncar-2012-slides.pdf` | 28 | `d29ab7822a31a437e980c1e29a97abc2178938c32a6a7e5e364c2414f97aa0b1` |

### Apache 2.0 licence


                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

   END OF TERMS AND CONDITIONS

   APPENDIX: How to apply the Apache License to your work.

      To apply the Apache License to your work, attach the following
      boilerplate notice, with the fields enclosed by brackets "[]"
      replaced with your own identifying information. (Don't include
      the brackets!)  The text should be enclosed in the appropriate
      comment syntax for the file format. We also recommend that a
      file or class name and description of purpose be included on the
      same "printed page" as the copyright notice for easier
      identification within third-party archives.

   Copyright [yyyy] [name of copyright owner]

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.

EXTERNAL COMPONENTS

Apache PDFBox includes a number of components with separate copyright notices
and license terms. Your use of these components is subject to the terms and
conditions of the following licenses.

Contributions made to the original PDFBox and FontBox projects:

   Copyright (c) 2002-2007, www.pdfbox.org
   All rights reserved.

   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions are met:

   1. Redistributions of source code must retain the above copyright notice,
      this list of conditions and the following disclaimer.

   2. Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.

   3. Neither the name of pdfbox; nor the names of its contributors may be
      used to endorse or promote products derived from this software without
      specific prior written permission.

   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
   AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
   IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
   ARE DISCLAIMED.  IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE
   FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
   DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
   SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
   CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
   LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
   OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
   SUCH DAMAGE.

Adobe Font Metrics (AFM) for PDF Core 14 Fonts

   This file and the 14 PostScript(R) AFM files it accompanies may be used,
   copied, and distributed for any purpose and without charge, with or without
   modification, provided that all copyright notices are retained; that the
   AFM files are not distributed without this file; that all modifications
   to this file or any of the AFM files are prominently noted in the modified
   file(s); and that this paragraph is not modified. Adobe Systems has no
   responsibility or obligation to support the use of the AFM files.

CMaps for PDF Fonts (http://opensource.adobe.com/wiki/display/cmap/Downloads)

   Copyright 1990-2009 Adobe Systems Incorporated.
   All rights reserved.

   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions
   are met:

   Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.

   Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

   Neither the name of Adobe Systems Incorporated nor the names of its
   contributors may be used to endorse or promote products derived from this
   software without specific prior written permission.

   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
   AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
   IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
   ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
   LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
   CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
   SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
   INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
   CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
   ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
   THE POSSIBILITY OF SUCH DAMAGE.

PaDaF PDF/A preflight (http://sourceforge.net/projects/padaf)

  Copyright 2010 Atos Worldline SAS

  Licensed by Atos Worldline SAS under one or more
  contributor license agreements.  See the NOTICE file distributed with
  this work for additional information regarding copyright ownership.
  Atos Worldline SAS licenses this file to You under the Apache License, Version 2.0
  (the "License"); you may not use this file except in compliance with
  the License.  You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

OSXAdapter

  Version: 2.0

  Disclaimer: IMPORTANT:  This Apple software is supplied to you by
  Apple Inc. ("Apple") in consideration of your agreement to the
  following terms, and your use, installation, modification or
  redistribution of this Apple software constitutes acceptance of these
  terms.  If you do not agree with these terms, please do not use,
  install, modify or redistribute this Apple software.

  In consideration of your agreement to abide by the following terms, and
  subject to these terms, Apple grants you a personal, non-exclusive
  license, under Apple's copyrights in this original Apple software (the
  "Apple Software"), to use, reproduce, modify and redistribute the Apple
  Software, with or without modifications, in source and/or binary forms;
  provided that if you redistribute the Apple Software in its entirety and
  without modifications, you must retain this notice and the following
  text and disclaimers in all such redistributions of the Apple Software.
  Neither the name, trademarks, service marks or logos of Apple Inc.
  may be used to endorse or promote products derived from the Apple
  Software without specific prior written permission from Apple.  Except
  as expressly stated in this notice, no other rights or licenses, express
  or implied, are granted by Apple herein, including but not limited to
  any patent rights that may be infringed by your derivative works or by
  other works in which the Apple Software may be incorporated.

  The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
  MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
  THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
  FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
  OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.

  IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
  OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
  INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
  MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
  AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
  STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
  POSSIBILITY OF SUCH DAMAGE.

  Copyright (C) 2003-2007 Apple, Inc., All Rights Reserved

### LLVM licence

==============================================================================
The LLVM Project is under the Apache License v2.0 with LLVM Exceptions:
==============================================================================

                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

    TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

    1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

    2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

    3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

    4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

    5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

    6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

    7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

    8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

    9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

    END OF TERMS AND CONDITIONS

    APPENDIX: How to apply the Apache License to your work.

      To apply the Apache License to your work, attach the following
      boilerplate notice, with the fields enclosed by brackets "[]"
      replaced with your own identifying information. (Don't include
      the brackets!)  The text should be enclosed in the appropriate
      comment syntax for the file format. We also recommend that a
      file or class name and description of purpose be included on the
      same "printed page" as the copyright notice for easier
      identification within third-party archives.

    Copyright [yyyy] [name of copyright owner]

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.


---- LLVM Exceptions to the Apache 2.0 License ----

As an exception, if, as a result of your compiling your source code, portions
of this Software are embedded into an Object form of such source code, you
may redistribute such embedded portions in such Object form without complying
with the conditions of Sections 4(a), 4(b) and 4(d) of the License.

In addition, if you combine or link compiled forms of this Software with
software that is licensed under the GPLv2 ("Combined Software") and if a
court of competent jurisdiction determines that the patent provision (Section
3), the indemnity provision (Section 9) or other Section of the License
conflicts with the conditions of the GPLv2, you may retroactively and
prospectively choose to deem waived or otherwise exclude such Section(s) of
the License, but only in their entirety and only with respect to the Combined
Software.

==============================================================================
Software from third parties included in the LLVM Project:
==============================================================================
The LLVM Project contains third party software which is under different license
terms. All such code will be identified clearly using at least one of two
mechanisms:
1) It will be in a separate directory tree with its own `LICENSE.txt` or
   `LICENSE` file at the top containing the specific license and restrictions
   which apply to that software, or
2) It will contain specific license and restriction terms at the top of every
   file.

==============================================================================
Legacy LLVM License (https://llvm.org/docs/DeveloperPolicy.html#legacy):
==============================================================================
University of Illinois/NCSA
Open Source License

Copyright (c) 2003-2019 University of Illinois at Urbana-Champaign.
All rights reserved.

Developed by:

    LLVM Team

    University of Illinois at Urbana-Champaign

    http://llvm.org

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal with
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

    * Redistributions of source code must retain the above copyright notice,
      this list of conditions and the following disclaimers.

    * Redistributions in binary form must reproduce the above copyright notice,
      this list of conditions and the following disclaimers in the
      documentation and/or other materials provided with the distribution.

    * Neither the names of the LLVM Team, University of Illinois at
      Urbana-Champaign, nor the names of its contributors may be used to
      endorse or promote products derived from this Software without specific
      prior written permission.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
CONTRIBUTORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS WITH THE
SOFTWARE.
