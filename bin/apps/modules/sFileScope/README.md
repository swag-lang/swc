# sFileScope

sFileScope is the universal read-only viewer shipped with Swag. One executable owns navigation,
drag and drop, the shared search and information bands, the basic text surface, and every
format-specific viewer. Global navigation and file information stay above the document; the
active viewer gets a dedicated tool band below it, visible only when that viewer has commands.

## Integrated viewer registry

`src/viewerindex.swg` is the only registry. It binds each stable key, display name, glyph, and set
of lowercase extensions or exact file names directly to a `ViewerCreate` function compiled into
sFileScope. There is no runtime index, dynamic library, exported entry point, or versioned ABI.

Several viewers may claim the same extension. The selector lists format-specific viewers first,
`Basic text` next when the file is readable UTF-8, then every viewer registered for `*`, each
beside the glyph its viewer owns. Changing the selector reuses a view already opened for the
current file or creates it on demand; it does not reopen the window.

The first choice is the default, and choosing another one is remembered for that kind of file: the
choice is kept against the viewer the file would have opened in, so turning one video into bytes
opens the next video in bytes whatever container it arrives in. Choosing the ordinary viewer back
removes the decision rather than recording one more. The stable key, not the display name, is what
the persisted state carries.

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
  are selectable, and the two of them that set their own reading measure justify their body
  column. Text selects across blocks with the pointer or Ctrl+A and copies with Ctrl+C, as plain
  text: inline formatting resolves to the words it decorated, a table to tabs and lines, and a
  formula to its mathematical source. Rendering is offline and executes no embedded HTML or
  script.
- `HTML` adapts the reusable GUI `HtmlView`. It streams document blocks into a centered page,
  keeps links explicit, follows the active palette, and applies the supported CSS subset. Head,
  script, style, template, and embedded-document content never executes.
- `Image` uses Pixel decoders for BMP, GIF, ICO, JPEG, PNG, TGA, TIFF, and WebP, plus Pixel's SVG
  parser. It provides zoom, pan, fit, actual size, rotation, transparency, and GIF playback.
- `Video` uses the Video and Audio modules for YUV4MPEG2, AVI, and ISO-BMFF streams. Its transport
  provides play/pause, stop, ten-second seeks, a time-based timeline, elapsed/total time, mute,
  volume, and matching keyboard controls. It indexes
  packets without decoding the file up front and materializes only the selected picture and the
  few audio buffers queued at the device. MP4, M4V, and MOV accept Motion JPEG or H.264 picture
  tracks and AAC-LC mono/stereo sound. The output-device sample cursor is the master clock: slow
  picture decoding drops to a clean video sync frame without moving or stretching sound.
- `Sound` uses the Audio module to stream PCM or float WAV files. Its transport provides the same
  basic time, seek, mute, volume, and keyboard controls as video. Playback does not retain the
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

The application stores its palette, language, window state, recent files, and remembered viewer
choices in the user's application-data folder. It toggles full screen with F11, navigates the
current folder with Left/Right, reloads with F5, opens with Ctrl+O, and accepts one file dropped
anywhere on the surface. Audio and video claim bare Left/Right for ten-second seeks while active,
and use Space for play/pause and M for mute. An
installer may run `sFileScope.exe --register-file-types`; normal launches never write the registry.

A right click names what a file offers. On the information band above the document it answers for
the open file, and on a panel row for the file that row names: show it in the system file explorer,
or hand it to the system chooser of applications. A row of the history offers two more, because
the history is the one list the reader owns: drop that file from it, or clear it entirely. Nothing
here writes to the file, and the chooser runs in its own process.

## Adding a viewer

Add implementation files under `src/viewers/<format>/`, expose one internal
`func create<Format>Viewer(const *ViewerRequest, *ViewerResult)`, and add that function with its
key, name, glyph, and selectors to `createViewerIndex`. The key is lowercase, never translated,
and never reused: it is the spelling a reader's remembered choice is stored under. The glyph is a
new 24-unit cell appended to `datas/icons.svg` with a matching `ViewerIcons` case in grid order. Create the document under `request.contentParent` and optional
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
