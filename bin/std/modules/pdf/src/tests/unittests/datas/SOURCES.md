# PDF fixture sources

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

The files are distributed under the Apache License 2.0; see
`LICENSE.apache-2.0.txt`.

## LLVM and Polly compatibility corpus

These files are unmodified copies from the LLVM tree at Swag repository commit
[`7328b93084641fe1a86577aefc98c093b26133e5`](https://github.com/swag-lang/swag/tree/7328b93084641fe1a86577aefc98c093b26133e5/llvm).
Together they add 354 real-world pages produced by several generations of PDF tools. They are
distributed under the LLVM Apache 2.0 license with exceptions; see `LLVM-LICENSE.txt`.

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
