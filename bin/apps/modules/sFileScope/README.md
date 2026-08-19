# sFileScope

sFileScope is the universal read-only viewer shipped with Swag. One executable owns navigation,
drag and drop, the shared search and information bands, the basic text surface, and every
format-specific viewer. Viewer selection and contextual actions share one compact bar, so the
document keeps the clear majority of the window.

## Integrated viewer registry

`src/viewerindex.swg` is the only registry. It binds each display name and set of lowercase
extensions or exact file names directly to a `ViewerCreate` function compiled into sFileScope.
There is no runtime index, dynamic library, exported entry point, or versioned ABI.

Several viewers may claim the same extension. The selector lists format-specific viewers first,
`Basic text` next when the file is readable UTF-8, then every viewer registered for `*`. The first
choice is the default. Changing the selector reuses a view already opened for the current file or
creates it on demand; it does not reopen the window.

Basic text is available for every readable text file. It loads small UTF-8 segments on demand and
stays about two viewports ahead, so a large source file does not need to fit in memory before its
first screen appears. Binary content directs the reader to the hexadecimal alternative instead of
guessing an encoding.

## Shipped viewers

- `Code` streams source with syntax coloring for Swag, C-family languages, JavaScript and
  TypeScript, Go, Rust, Python, shell languages, structured data, shaders, build files, and the
  other extensions declared by the registry. Swag vocabulary follows the compiler's current
  keywords, intrinsics, directives, and modifiers. HTML keeps its rendered viewer first and offers
  Code as the source alternative.
- `Markdown` adapts the reusable GUI `Markdown.View`. It supports headings, prose, GFM alerts,
  nested lists and tasks, fenced code, aligned tables, metadata, footnotes, references, a table of
  contents, inline formatting, and native mathematical layout. Reader themes and reading widths
  are selectable. Rendering is offline and executes no embedded HTML or script.
- `HTML` adapts the reusable GUI `HtmlView`. It streams document blocks into a centered page,
  keeps links explicit, follows the active palette, and applies the supported CSS subset. Head,
  script, style, template, and embedded-document content never executes.
- `Image` uses Pixel decoders for BMP, GIF, ICO, JPEG, PNG, TGA, TIFF, and WebP, plus Pixel's SVG
  parser. It provides zoom, pan, fit, actual size, rotation, transparency, and GIF playback.
- `Video` uses the Video module for silent YUV4MPEG2, AVI, and ISO-BMFF streams. It indexes frame
  payloads without decoding the file up front and materializes only the selected frame. MP4, M4V,
  and MOV currently accept Motion JPEG video; unsupported tracks remain inspectable as binary.
- `Sound` uses the Audio module to stream PCM or float WAV files. Playback does not retain the
  complete payload, and a low-priority worker builds the waveform from bounded blocks.
- `Font` renders TrueType fonts and the first face of a TrueType collection as a live specimen.
  Its paged character map walks mapped Unicode scalars without materializing the whole map.
- `Binary` displays a format's structure tree with field name, decoded value, file offset, and
  meaning. It recognizes Windows images, COFF and `ar` libraries, ELF, Mach-O, WebAssembly, ZIP,
  RIFF, sfnt fonts, Windows icons, and Swag Chunk Containers. Unknown files still receive signature,
  size, and entropy analysis.
- `Hexadecimal` is available for every file. It pages through 64 KiB at a time, uses 64-bit
  offsets, and supports independent scalar width, representation, and byte order.

Text-oriented viewers handle normal keyboard and scrollbar navigation while content is streaming.
Home, End, distant scrollbar jumps, and search open a bounded resident window near the requested
offset. Ctrl+F scans in asynchronous 256 KiB chunks, while viewers such as PDF can replace that
scan with format-aware search. The information band shows a spinner while the active viewer is
still producing visible content, and switching viewers retires hidden progressive work.

The application stores its palette, language, window state, and recent files in the user's
application-data folder. It navigates the current folder with Left/Right, reloads with F5, opens
with Ctrl+O, and accepts one file dropped anywhere on the surface. An installer may run
`sFileScope.exe --register-file-types`; normal launches never write the registry.

## Adding a viewer

Add implementation files under `src/viewers/<format>/`, expose one internal
`func create<Format>Viewer(const *ViewerRequest, *ViewerResult)`, and add that function with its
selectors to `createViewerIndex`. Create the document under `request.contentParent` and optional
compact commands under `request.commandParent`. On decode failure, leave `result.view` null and
return the exact reason through `result.failureReason`; the application presents every failure on
the same error surface. A viewer may also provide format details, byte-offset reveal, format-aware
search, progressive-loading state, and late failure reporting through the shared result contract.

Keep tests at `src/tests/viewer.<format>.test.swg`, fixtures in `src/tests/datas`, and image goldens
in `src/tests/goldens`. Run a focused test with:

```text
swc tools/apps.swgs dm test sFileScope --test-file viewer.<format>.test.swg
```

`swc tools/apps.swgs dm build sFileScope` builds one executable containing all viewers and lets
the workspace publisher place its standard-module runtime dependencies beside it.
