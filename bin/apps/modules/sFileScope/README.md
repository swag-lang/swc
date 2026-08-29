# sFileScope

sFileScope is the universal read-only viewer shipped with Swag. One executable owns navigation,
drag and drop, the shared search and information bands, the basic text surface, and every
format-specific viewer. Global navigation and file information stay above the document. A viewer
can place compact actions in the shared action bar, either centered or beside shared search, values
at the trailing edge of the information band, and wider controls in a dedicated lower tool band
that appears only when it is needed.

## Integrated viewer registry

`src/viewerindex.swg` is the only registry. It binds each stable key, display name, glyph, smoke
fixture, and set of lowercase extensions or exact file names directly to a `ViewerCreate` function
compiled into sFileScope. Image, video, and sound selectors are derived from their modules' decoder
registries, so their application coverage cannot drift behind the formats the modules expose.
There is no runtime index, dynamic library, exported entry point, or versioned ABI.

Several viewers may claim the same extension. The selector lists format-specific viewers first,
`Basic text` next when the file is readable UTF-8, then the `Binary` and `Hexadecimal` fallbacks,
each beside the glyph its viewer owns. Changing the selector reuses a view already opened for the
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
  other extensions and common exact file names declared by the registry. An otherwise unregistered
  script with a shebang is recognized from its first line. Swag vocabulary follows the compiler's
  current keywords, intrinsics, directives, and modifiers. HTML keeps its rendered viewer first
  and offers Code as the source alternative.
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
- `Table` reads CSV, TSV, and tabular `.tab` files into a virtual multi-column list. It detects
  comma, semicolon, tab, or pipe separators, understands quoted separators and embedded line
  breaks, keeps the first row as a fixed header, and participates in shared search. Source files
  are capped at 32 MiB; larger tables retain the bounded streamed basic-text alternative.
- `Image` uses Pixel decoders for BMP, GIF, ICO, JPEG, PNG, TGA, TIFF, and WebP, plus Pixel's SVG
  parser. Its centered action group provides zoom, pan, fit, actual size, rotation in either
  direction, horizontal and vertical reflection, reset, and GIF playback. The information band
  reports zoom and temporary orientation, so still images need no lower tool band.
- `Video` uses the Video and Audio modules for YUV4MPEG2, AVI, ISO-BMFF, and Matroska streams. Its
  transport provides play/pause, stop, ten-second seeks, a time-based timeline, elapsed/total time,
  mute, volume, and matching keyboard controls. It indexes packets without decoding the file up
  front and materializes only the selected picture and the few audio buffers queued at the device.
  AVI accepts Motion JPEG, MPEG-4 Part 2, or uncompressed picture tracks and integer PCM sound.
  MP4, M4V, and MOV accept Motion JPEG, H.264, or H.265 picture tracks and AAC-LC mono/stereo
  sound. MKV accepts H.264, H.265, or MPEG-4 Part 2 pictures and every AAC-LC, AC-3, independent
  E-AC-3, DTS Core, FLAC, MPEG Layer III, Vorbis, or Opus track, with a selector when several are
  present. The
  output-device sample cursor is the master clock: slow picture decoding drops to a clean video
  sync frame without moving or stretching sound.
- `Sound` uses the Audio module to stream WAV (PCM, float, and ADPCM), FLAC, MP3, AAC, AC-3, E-AC-3, DTS,
  Ogg Vorbis, and Opus files. Its transport provides the same
  basic time, seek, mute, volume, and keyboard controls as video. Playback does not retain the
  complete payload, and a low-priority worker builds the waveform from bounded blocks.
- `Font` renders TrueType fonts and the first face of a TrueType collection as a live specimen.
  Its paged character map walks mapped Unicode scalars without materializing the whole map.
- `MIDI` parses Standard MIDI Files into a dedicated piano roll. It shows musical duration,
  tempo, meter, key signature, named tracks and note ranges, offers an all-tracks or per-track
  view, and provides horizontal zoom without synthesizing or executing file content.
- `Binary` displays a format's structure tree with field name, decoded value, file offset, and
  meaning. It recognizes Windows images, COFF and `ar` libraries, ELF, Mach-O, WebAssembly, ZIP,
  RIFF, Standard MIDI Files, sfnt fonts, Windows icons, and Swag Chunk Containers. Unknown files
  still receive signature, size, and entropy analysis. Shared search indexes every decoded report
  column and reveals folded matches by outlining only the matching text. Its viewer-glyph menu sits
  in the shared action bar beside search; it copies rows or the report, expands or folds the tree,
  jumps to a file offset, and walks visited rows backward or forward.
- `Hexadecimal` is available for every file. It keeps one 256 KiB resident window whose reads are
  aligned to 64 KiB boundaries, uses 64-bit offsets, and supports independent scalar width,
  representation, and byte order. Its information-band inspector reports the exact caret offset,
  selection length, active value, and the same bytes as signed, unsigned, hexadecimal, floating
  point, and printable readings. Search accepts byte and nibble wildcards (`4D 5A ??`, `?A`,
  `A?`), exact UTF-8 through `text:`, and the active scalar and byte order through `value:`. Every
  visible result is marked while the shared animated marker identifies the current occurrence.

Text-oriented viewers handle normal keyboard and scrollbar navigation while content is streaming.
Home, End, distant scrollbar jumps, and search open a bounded resident window near the requested
offset. Ctrl+F scans in asynchronous 256 KiB chunks, while viewers such as PDF and Binary replace
that scan with format-aware search. Search is case-insensitive by default; `Aa` requires the same
case and the bracketed word glyph restricts matches to whole words. The result counter reports the
current and total occurrences, F3 and Shift+F3 move forward and backward with wrapping, and every
viewer supplies
only match geometry to the same animated, theme-derived current-result marker. Binary-pattern
search hides the text-only case and whole-word switches and explains its syntax in the field.
The information
band shows a spinner while the active viewer is still producing visible content, and switching
viewers retires hidden progressive work.

The application stores its palette, language, window state, recent files, bounded recent-folder
history, and remembered viewer choices in the user's application-data folder. It toggles full
screen with F11, navigates the current folder with Left/Right, reloads with F5, opens with Ctrl+O,
and accepts one file dropped anywhere on the surface. The recent and current-folder lists show the
glyph of each file's default viewer; the current-folder heading opens the recent-folder menu and
returns to the last file viewed in the selected folder. Audio and video claim bare Left/Right for
ten-second seeks while active, and use Space for play/pause and M for mute. An
installer may run `sFileScope.exe --register-file-types`; normal launches never write the registry.

A common action-bar button opens the current file with the operating system's registered default
application. A right click names the same action and the rest of what a file offers. On the
information band above the document it answers for the open file, and on a panel row for the file
that row names: show it in the system file explorer, open it with the default application, hand it
to the system chooser of applications, or copy its full path or file name. A row of the history
offers two more, because the history is the one list the reader owns: drop that file from it, or
clear it entirely. Nothing here writes to the file, and external applications run in their own
processes.

## Adding a viewer

Every viewer, including Basic text, is a plugin described by `FileScope.Plugin`. The shared
`filescopeviewer` module owns this versioned source-level contract; the application owns only a
generic registry and a `FileScope.Host` implementation. No plugin receives `ViewerWindow`, its
bars, its session structure, or application-private callbacks.

Add implementation files under `src/viewers/<format>/` and expose one internal
`func create<Format>Viewer(host: FileScope.Host)`. Register its descriptor in
`createViewerPluginRegistry` with a stable lowercase key, display-name resolver, icon provider,
immutable smoke fixture, selectors, and optional content probe. A plugin calls `attachView` for its
document and can create at most one action, information, and lower command group through the host.
It declares optional search and progressive-lifecycle behavior through `setSearch` and
`setLifecycle`; retained asynchronous notifications come only from `host.services()`.

The fixture lives in `src/tests/datas`, is unique to that descriptor, and is a valid file the
plugin can open. The key is never translated or reused because remembered viewer choices persist
it. A built-in glyph remains a 24-unit cell in `datas/icons.svg` with a matching `ViewerIcons` case
in grid order. Reject malformed content with the exact decoder reason before attaching a view; the
application presents every plugin failure on the same error surface and owns cleanup of all
contributed windows.

The registry accepts descriptors it did not compile into its built-in catalog, and its selection
pipeline contains no viewer-kind branches. Runtime discovery of external binaries is intentionally
future work: it needs a native entry point, trust and discovery policy, and ABI adapter that checks
`FileScope.ViewerApiVersion`. The current shared module establishes the clean plugin boundary
without claiming that arbitrary DLL loading is already safe or supported.

Keep tests at `src/tests/viewer.<format>.test.swg`, fixtures in `src/tests/datas`, and image goldens
in `src/tests/goldens`. Run a focused test with:

```text
swc tools/apps.swgs dm test sFileScope --test-file viewer.<format>.test.swg
```

`swc tools/apps.swgs dm build sFileScope` builds one executable containing all viewers and lets
the workspace publisher place its standard-module runtime dependencies beside it.

`swc tools/apps.swgs dm smoke sFileScope` opens every plugin's registered fixture in order and
selects that plugin explicitly. It keeps progressive content visible long enough to exercise late
failures, waits while a viewer has no presentable content, and returns a nonzero exit code when a
fixture is missing or a plugin cannot open it.
