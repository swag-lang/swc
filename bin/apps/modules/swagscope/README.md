# Swag Scope

Swag Scope is the universal read-only viewer shipped with Swag. One executable owns navigation,
drag and drop, the shared search and information bands, the basic text surface, and every
format-specific viewer. Global navigation, search, and file information stay above the document.
Dynamic values such as zoom sit at the trailing edge of the information band and open the actions
that change them; every viewer-specific command group is centered in one lower band that appears
only when it is needed.

## Integrated viewer registry

`src/viewerpluginregistry.swg` is the only registry, and it holds no format knowledge: an ordered
list of descriptors, each returned by the viewer that implements it. A descriptor binds a stable
key, a display name, a glyph, a smoke fixture, and a set of lowercase extensions or exact file names
to one creation callback. Image, video, and sound selectors are derived from their modules' decoder
registries, so their application coverage cannot drift behind the formats the modules expose.
There is no runtime index, dynamic library, exported entry point, or versioned ABI yet.

Several viewers may claim the same extension. The selector lists format-specific viewers first,
`Basic text` next when nothing else claims the file and it reads as text, or when the file is one
of the text formats that surface names, then the `Binary` and `Hexadecimal` fallbacks, each beside
the glyph its viewer owns. Changing the selector reuses a view already opened for the
current file or creates it on demand; it does not reopen the window.

The first choice is the default, and choosing another one is remembered for that kind of file: the
choice is kept against the viewer the file would have opened in, so turning one video into bytes
opens the next video in bytes whatever container it arrives in. Choosing the ordinary viewer back
removes the decision rather than recording one more. The stable key, not the display name, is what
the persisted state carries.

Basic text is available for a readable text file no other viewer answers for, and for the text
formats it owns by name — a subtitle track is played against its film and is still a text file a
reader may want to read. It never offers itself for a document another viewer claims: a PDF, an
office file and a font all open with enough printable bytes to pass a content probe, and offering
to read one as a page of text says something untrue about the file. It loads small UTF-8 segments
on demand and stays about two viewports ahead, so a large source file does not need to fit in
memory before its first screen appears. Binary content directs the reader to the hexadecimal
alternative instead of guessing an encoding.

## Shipped viewers

- `Code` streams source with syntax coloring for Swag, C-family languages, JavaScript and
  TypeScript, Go, Rust, Python, shell languages, structured data, shaders, build files, and the
  other extensions and common exact file names declared by the registry. An otherwise unregistered
  script with a shebang is recognized from its first line. Swag vocabulary follows the compiler's
  current keywords, intrinsics, directives, and modifiers. HTML keeps its rendered viewer first
  and offers Code as the source alternative. Its information-band zoom uses the same percentage
  menu and keyboard gestures as the other text readers.
- `Markdown` adapts the reusable GUI `Markdown.View`. It supports headings, prose, GFM alerts,
  nested lists and tasks, fenced code, aligned tables, metadata, footnotes, references, a table of
  contents, inline formatting, and native mathematical layout. Reader themes and reading widths
  are selectable, and the two of them that set their own reading measure justify their body
  column. Text selects across blocks with the pointer or Ctrl+A and copies with Ctrl+C, as plain
  text: inline formatting resolves to the words it decorated, a table to tabs and lines, and a
  formula to its mathematical source. Rendering is offline and executes no embedded HTML or
  script. Reading width and appearance stay in the centered lower band; zoom is a clickable
  information-band percentage.
- `HTML` adapts the reusable GUI `HtmlView`. It streams document blocks into a centered page,
  keeps links explicit, follows the active palette, and applies the supported CSS subset. Head,
  script, style, template, and embedded-document content never executes. Default document text
  size follows the common zoom control.
- `Table` reads CSV, TSV, and tabular `.tab` files into a virtual multi-column list. It detects
  comma, semicolon, tab, or pipe separators, understands quoted separators and embedded line
  breaks, keeps the first row as a fixed header, and participates in shared search. Source files
  are capped at 32 MiB; larger tables retain the bounded streamed basic-text alternative.
- `Image` maps encoded raster and SVG input read-only, so decoding does not first allocate a
  second file-sized heap buffer. It uses Pixel decoders for BMP, GIF, ICO, JPEG, PNG, TGA, TIFF,
  and WebP, plus Pixel's SVG parser. Its centered lower group provides sibling navigation,
  orientation commands, and GIF playback. The clickable information-band percentage provides zoom
  presets, fit, and actual size while also reporting temporary orientation.
- `Video` uses the Video and Audio modules for YUV4MPEG2, AVI, ISO-BMFF, and Matroska streams. Its
  transport provides play/pause, stop, ten-second seeks, a time-based timeline, elapsed/total time,
  mute, volume, and matching keyboard controls, plus a settings menu offering loop playback and a
  0.25x-2x playback rate whose pitch follows the rate and whose time labels stay in source time.
  It indexes packets without decoding the file up
  front and materializes only the selected picture and the few audio buffers queued at the device.
  AVI accepts Motion JPEG, MPEG-4 Part 2, or uncompressed picture tracks and integer PCM sound.
  MP4, M4V, and MOV accept Motion JPEG, H.264, or H.265 picture tracks and AAC-LC mono/stereo
  sound. MKV accepts H.264, H.265, or MPEG-4 Part 2 pictures and every AAC-LC, AC-3, independent
  E-AC-3, DTS Core, FLAC, MPEG Layer III, Vorbis, or Opus track, with a selector when several are
  present. The decoded run-ahead targets a 64 MiB budget, with a two-picture floor for
  high-resolution streams.
  The output-device sample cursor is the master clock: slow picture decoding drops to a clean
  video sync frame without moving or stretching sound.
- `Sound` uses the Audio module to stream WAV (PCM, float, and ADPCM), FLAC, MP3, AAC, AC-3, E-AC-3, DTS,
  Ogg Vorbis, and Opus files. Its transport provides the same
  basic time, seek, mute, volume, and keyboard controls as video. Playback does not retain the
  complete payload, and a low-priority worker builds the waveform from bounded blocks.
- `Font` renders TrueType fonts and the first face of a TrueType collection as a live specimen.
  Its paged character map walks mapped Unicode scalars without materializing the whole map; the
  current range opens shortcuts to common Unicode blocks.
- `MIDI` parses Standard MIDI Files into a dedicated piano roll. It shows musical duration,
  tempo, meter, key signature, named tracks and note ranges, offers an all-tracks or per-track
  view, and provides horizontal zoom through the common information-band control without
  synthesizing or executing file content.
- `Archive` opens ZIP and ZIP64 containers, including JAR, APK, EPUB, office and package formats,
  as a real hierarchical file browser. Selecting an entry prepares a bounded temporary copy,
  verifies its declared size and CRC-32, and hosts that copy through the ordinary viewer registry
  in the adjacent preview pane. Stored and Deflate entries are decoded; encrypted entries,
  multi-disk archives, unsupported compression methods, oversized directories, and previews above
  256 MiB stop with an exact explanation. Nested archives therefore open as nested archive
  browsers without a second rendering path. The master-detail surface keeps the archive tree and
  the viewed content visible together, so archive navigation does not require global document tabs.
- `Binary` displays a format's structure tree with field name, decoded value, file offset, and
  meaning. Its bounded 64 MiB prefix is read through a mapping and scanned pages are released from
  the process working set once the owned report is built. It recognizes Windows images, COFF and
  `ar` libraries, ELF, Mach-O, WebAssembly, ZIP, RIFF, Standard MIDI Files, sfnt fonts, Windows
  icons, and Swag Chunk Containers. Unknown files still receive signature, size, and entropy
  analysis. Shared search indexes every decoded report column and reveals folded matches by
  outlining only the matching text. A compact centered lower
  group walks visited rows backward or forward and opens the structure-command menu for copying,
  expansion, collapse, and file-offset navigation.
- `Hexadecimal` is available for every file. It keeps one 256 KiB resident window whose reads are
  aligned to 64 KiB boundaries, uses 64-bit offsets, and supports independent scalar width,
  representation, explicit Little/Big byte order, and fixed-width font zoom. Its information-band
  inspector reports the exact caret offset and file percentage, selection length, active value,
  and the same bytes as signed, unsigned, hexadecimal, binary, octal, boolean, floating-point, and
  printable readings. Go To accepts hexadecimal, `0d` decimal, percentage, `caret`, `filesize`, and
  signed caret-relative positions. A visible commands button exposes copy, navigation, and row
  layout without requiring a right click. Search accepts byte and nibble wildcards (`4D 5A ??`, `?A`,
  `A?`), exact UTF-8 through `text:`, and the active scalar and byte order through `value:`. Every
  visible result is marked while the shared animated marker identifies the current occurrence.
  A cancellable, streaming analysis of the selection or whole file adds a 256-value byte map,
  exact counts, entropy, zero and printable ratios, and bounded inferred ASCII and UTF-16 strings;
  selecting an inferred string returns to its source bytes, and Analyze reruns on that live
  selection instead of replaying the range that originally opened the panel.

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
screen with F11 or the action bar's top-right button — full screen hides every bar and panel and
reveals the top or bottom chrome while the pointer rests at that screen edge — navigates the
current folder with Left/Right, reloads with F5, opens with Ctrl+O,
and accepts one file dropped anywhere on the surface. The recent and current-folder lists show the
glyph of each file's default viewer; the current-folder heading opens the recent-folder menu and
returns to the last file viewed in the selected folder. Audio and video claim bare Left/Right for
ten-second seeks while active, and use Space for play/pause and M for mute. An
installer may run `swagscope.exe --register-file-types`; normal launches never write the registry.

A common action-bar button opens the current file with the operating system's registered default
application. A right click names the same action and the rest of what a file offers. On the
information band above the document it answers for the open file, and on a panel row for the file
that row names: show it in the system file explorer, open it with the default application, hand it
to the system chooser of applications, or copy its full path or file name. A row of the history
offers two more, because the history is the one list the reader owns: drop that file from it, or
clear it entirely. Nothing here writes to the file, and external applications run in their own
processes.

## The viewer plugin API

`src/api/` is the whole surface a viewer is written against, published under the `Viewer`
namespace: `Viewer.Plugin` describes a viewer, `Viewer.Host` is what its creation callback
receives, `Viewer.Embedded` hosts a file through the same registry inside another viewer, and
`Viewer.SearchApi`, `Viewer.LifecycleApi`, `Viewer.BackgroundLoad`, and the search
and clock helpers beside them are the support the host offers. Nothing else is available to a
viewer. No plugin receives `ViewerWindow`, its bars, its session structure, or application-private
callbacks, and the application never names a format.

Every viewer is written this way, the plain text one included. That is the point of the
arrangement: a viewer compiled into the executable and a viewer that will one day arrive as a
separate binary have the same shape, so the API is kept honest by the fifteen viewers already
using it rather than by intention. Runtime discovery of external binaries is future work — it
needs a native entry point, a trust and discovery policy, and an ABI adapter that checks
`Viewer.ApiVersion` — and the source API deliberately does not pretend that loading arbitrary
libraries is already safe or supported.

## Adding a viewer

Put the implementation under `src/viewers/<format>/` and give the folder three things: one
`func <format>ViewerPlugin()->Viewer.Plugin` describing the viewer, one
`func create<Format>Viewer(host: Viewer.Host)` building it, and a `localization.swg` owning its
own strings. Then add one `register` line to `createViewerPluginRegistry`, in the position the
viewer should be offered from. That is the only file outside the folder that changes.

The descriptor carries a stable lowercase key, a static or resolved display name, the vector
document and cell its glyph lives in, an immutable smoke fixture, its selectors, an optional
content probe, and an optional `attach` that prepares the viewer for the application it joined.
A plugin publishes its embedded translations from `attach`, so its name reads in the reader's
language before any file is opened.

The creation callback calls `attachView` for its document and can create at most one action,
information, and lower command group through the host, plus one optional side panel. It declares
optional search and progressive-lifecycle behavior through `setSearch` and `setLifecycle`;
retained asynchronous notifications come only from `host.services()`. Reject malformed content
with the exact decoder reason before attaching a view; the application presents every plugin
failure on the same error surface and owns cleanup of all contributed windows.

The fixture lives in `src/tests/datas`, is unique to that descriptor, and is a valid file the
plugin can open. The key is never translated or reused because remembered viewer choices persist
it. A built-in glyph remains a 24-unit cell in `datas/icons.svg` with a matching `ViewerIcons`
case in grid order; a separately built plugin would name a cell of the document it embeds itself.


Keep tests at `src/tests/viewer.<format>.test.swg`, fixtures in `src/tests/datas`, and image goldens
in `src/tests/goldens`. Run a focused test with:

```text
swc tools/apps.swgs dm test swagscope --test-file viewer.<format>.test.swg
```

`swc tools/apps.swgs dm build swagscope` builds one executable containing all viewers and lets
the workspace publisher place its standard-module runtime dependencies beside it.

`swc tools/apps.swgs dm smoke swagscope` opens every plugin's registered fixture in order and
selects that plugin explicitly. It keeps progressive content visible long enough to exercise late
failures, waits while a viewer has no presentable content, and returns a nonzero exit code when a
fixture is missing or a plugin cannot open it.
