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

