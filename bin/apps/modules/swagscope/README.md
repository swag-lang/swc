# Swag Scope

## Online movie posters and music covers

Folder exploration automatically looks up film posters and synopses in the Apple iTunes Search
API, direction, cast and IMDb ratings through Wikipedia and Wikidata, and album information and artwork through MusicBrainz and Cover Art Archive. No account
or API key is needed. Two lens entries of the explored folder turn either lookup off. Film filenames and music
tags are sent to these public services to find a match; only a film that alone answers to its
title, and to its year when the file name gives one, is taken, questions to the Apple catalogue
stand apart, and uncertain or unavailable results fall back to local previews. Film descriptions, credits and IMDb ratings are shown where available in the
sources. Cached results expire after 120 days. Wikipedia text is available under CC BY-SA; individual
images have their own licenses, which can be checked from the linked source article.

## Explore folders and archives

Opening a folder, or choosing Explore Folder (`Ctrl+E`), shows it as a page: its path, its name
as the title, how much it holds, and quiet menus choosing the order and the way of showing it —
names, sortable details, or small, medium and large thumbnails. ZIP files use the same navigation.
Every tile has the same size and the grid fills the page: a mixed folder shows each file on a
tile a little wider than tall, a folder of films its posters upright, with the name and one mono
line of facts under each. A slash or Ctrl+F reveals the filter.
The item chosen is ringed in Arc and described in the information sheet (`I`). An archive offers
Extract All… on its title line and Extract… in the sheet: the files go into a folder the reader
chooses, a file already there is kept, and a toast says how it went. Double-click or press Enter to open an item; closing its viewer returns to the
explorer with the selection and display mode preserved. Opening an ordinary file directly still
opens its viewer without requiring exploration. The optional left panel retains recent files and
shows the current location's subfolders. Alt+Left/Right navigate history, Alt+Up or Backspace goes
up, and F5 refreshes the location.

Enumeration, metadata, sorting, archive extraction and thumbnail decoding run asynchronously.
Lists and thumbnail grids render only their visible rows. A reusable child process renders
thumbnails through the existing viewer registry, including documents, source code, fonts and
audio. A viewer can optionally provide `Viewer.Plugin.thumbnail` as a direct image decoder;
otherwise its ordinary viewer renders offscreen with `Viewer.Host.isThumbnail()` set. This mode
must not play media or persist reader preferences. One request runs at a time, obsolete requests
are cancelled, and at most 128 thumbnails are retained in the renderer. A decoder failure or
timeout leaves the file's type icon available for opening it normally.

## Integrated viewer registry

`src/viewerpluginregistry.swg` is the only registry, and it holds no format knowledge: an ordered
list of descriptors, each returned by the viewer that implements it. A descriptor binds a stable
key, a display name, a glyph, a smoke fixture, and a set of lowercase extensions or exact file names
to one creation callback. Image, video, and sound selectors are derived from their modules' decoder
registries, so their application coverage cannot drift behind the formats the modules expose.
There is no runtime index, dynamic library, exported entry point, or versioned ABI yet.

A file is classified in three passes: its name, then its content, then the fallbacks. Several
viewers may claim the same extension, so the selector lists format-specific viewers first, then the
viewers that recognized the file from its own bytes, then `Basic text` when the file reads as text
and nothing that claimed it reads as something else, and finally the `Binary` and `Hexadecimal`
fallbacks, each beside the glyph its viewer owns. Changing the selector reuses a view already
opened for the current file or creates it on demand; it does not reopen the window. A video or a
sound that was playing pauses when another viewer takes its place, and is still paused when the
reader comes back to it.

The content pass is what a name cannot answer. A descriptor may carry a probe, and the host reads
the first four kilobytes of the file once and shows the same bytes to every one of them, so an
extensionless note, a log named `.dat`, a UTF-16 export, a renamed PDF, font, MIDI file, ZIP
container or HTML page all reach the viewer that can open them. A probe sees whether an earlier
viewer already claimed the file, which is how a signature states a fact while a last-resort reader
declines what a format viewer took.

The first choice is the default, and choosing another one is remembered for that kind of file: the
choice is kept against the viewer the file would have opened in, so turning one video into bytes
opens the next video in bytes whatever container it arrives in. Choosing the ordinary viewer back
removes the decision rather than recording one more. The stable key, not the display name, is what
the persisted state carries.

Basic text is available for a readable text file no other viewer answers for, for the text formats
it owns by name, and for every format whose descriptor declares that its bytes are text: Markdown,
HTML, source code, tables and subtitles are documents and are also files a reader may want to read
raw, so they offer the rendered document first and its source right after it. It never offers
itself for a document another viewer claims as binary: a PDF, an office file and a font all open
with enough printable bytes to pass a content probe, and offering to read one as a page of text
says something untrue about the file. It loads small UTF-8 segments
on demand and stays about two viewports ahead, so a large source file does not need to fit in
memory before its first screen appears. Its options wrap long lines, choose the
encoding, and number the lines, counted in the units of the file's encoding across the whole file;
the numbering follows the reader to the next file.
Binary content directs the reader to the hexadecimal alternative instead of guessing an encoding.

## Shipped viewers

- `Code` streams source with syntax coloring for Swag, C-family languages, JavaScript and
  TypeScript, Go, Rust, Python, shell languages, structured data, shaders, build files, and the
  other extensions and common exact file names declared by the registry. An otherwise unregistered
  script with a shebang is recognized from its first line. Swag vocabulary follows the compiler's
  current keywords, intrinsics, directives, and modifiers. A gutter numbers the lines of the whole
  file, including a window streamed from deep inside a long one. HTML keeps its rendered viewer first
  and offers Code as the source alternative. Its zoom uses the same percentage
  menu and keyboard gestures as the other text readers. Code reads in a centered column of at most
  900 pixels, and Basic text as prose: a 680-pixel column of the body face at 16 on a 29 pitch.
- `Markdown` adapts the reusable GUI `Markdown.View`. It supports headings, prose, GFM alerts,
  nested lists and tasks, fenced code, aligned tables, metadata, footnotes, references, a table of
  contents, inline formatting, and native mathematical layout. Reader themes and reading widths
  are selectable, and the two of them that set their own reading measure justify their body
  column. Text selects across blocks with the pointer or Ctrl+A and copies with Ctrl+C, as plain
  text: inline formatting resolves to the words it decorated, a table to tabs and lines, and a
  formula to its mathematical source. Rendering is offline and executes no embedded HTML or
  script. Reading width and appearance are the options of the viewer; zoom is a clickable
  percentage on the line of readings. When the window leaves room, the left margin lists the
  headings of the first two levels, the one being read on an Arc rule, and a thin Arc thread along
  the top edge grows with the share of the document already read.
  GitHub, Newsprint, Night, Pixyll, and Whitey follow their Typora typography, including heading
  weights, italics, line boxes, collapsing block margins, and heading rules. Fonts resolve from
  installed system families with the theme's fallback order; missing optional fonts are never
  downloaded or installed.
- `HTML` adapts the reusable GUI `HtmlView`. It streams document blocks into a centered page,
  keeps links explicit, follows the active palette, and applies the supported CSS subset. Head,
  script, style, template, and embedded-document content never executes. Default document text
  size follows the common zoom control.
- `PDF` displays pages progressively as they enter the viewport, with text selection, shared
  document search, zoom, and bookmark navigation in the outline panel. Encrypted documents are
  unsupported, and embedded actions are ignored rather than executed.
- `Table` reads CSV, TSV, and tabular `.tab` files into a virtual multi-column list. It detects
  comma, semicolon, tab, or pipe separators, understands quoted separators and embedded line
  breaks, keeps the first row as a fixed header, and participates in shared search. A click on a
  header sorts the rows by that column, quantities as numbers and words in natural order, with
  empty cells last; columns of quantities are aligned on the right. Ctrl+C copies the selected
  rows with their complete values, tab-separated, ready to paste into a spreadsheet. Source files
  are capped at 32 MiB; larger tables retain the bounded streamed basic-text alternative.
- `Image` maps encoded raster and SVG input read-only, so decoding does not first allocate a
  second file-sized heap buffer. It uses Pixel decoders for BMP, DDS, EXR, GIF, ICO, JPEG, KTX2,
  PNG, PSD, QOI, TGA, TIFF, and WebP, plus Pixel's SVG parser. It plays GIF, APNG, and WebP
  animations and navigates TIFF pages, icon variants, PSD raster layers, texture subresources,
  and EXR parts within Pixel's supported subsets. A photograph stands upright as the EXIF
  orientation its camera recorded asks, in the viewer and in its thumbnail. Ctrl+C, or Copy image in
  the orientation menu, puts the upright picture on the clipboard. PSD layer effects and masks are not rendered;
  unsupported compression and image layouts report a decoder error. Its centered lower group
  provides sibling navigation, orientation commands, and playback. The clickable
  percentage provides zoom presets, fit, and actual size while also reporting temporary orientation.
- `Video` uses the Video and Audio modules for YUV4MPEG2, AVI, ISO-BMFF, and Matroska streams. Its
  transport provides play/pause, stop, ten-second seeks, a time-based timeline, elapsed/total time,
  mute, volume, and matching keyboard controls, plus one options button gathering the play mode,
  a 0.25x-2x playback rate whose pitch follows the rate and whose time labels stay in source time,
  the sound track, and the subtitle tracks, style and delay. The rate shows beside the button
  while it is not the normal one.
  It indexes packets without decoding the file up front and keeps bounded picture and audio
  queues alongside codec reference buffers.
  AVI accepts Motion JPEG, MPEG-4 Part 2, or uncompressed picture tracks and integer PCM sound.
  MP4, M4V, and MOV accept Motion JPEG, H.264, or H.265 picture tracks and AAC-LC mono/stereo
  sound. MKV accepts H.264, H.265, or MPEG-4 Part 2 pictures and every AAC-LC, AC-3, independent
  E-AC-3, DTS Core, FLAC, MPEG Layer III, Vorbis, or Opus track, chosen among the options when
  several are present. The decoded run-ahead targets a 64 MiB budget, with a two-picture floor for
  high-resolution streams.
  The output-device sample cursor is the master clock: slow picture decoding drops to a clean
  video sync frame without moving or stretching sound.
- `Sound` uses the Audio module to stream WAV (PCM, float, and ADPCM), FLAC, MP3, AAC, AC-3, E-AC-3, DTS,
  Ogg Vorbis, and Opus files. Its transport provides the same
  basic time, seek, mute, volume, and keyboard controls as video, and names the recording by the title,
  artist, album, and year of its ID3 or Vorbis tags. Playback does not retain the
  complete payload, and a low-priority worker builds the waveform from bounded blocks.
- `Font` renders TrueType fonts and the first face of a TrueType collection as a live specimen.
  Its paged character map walks mapped Unicode scalars without materializing the whole map; the
  current range opens shortcuts to common Unicode blocks.
- `MIDI` parses Standard MIDI Files into a dedicated piano roll. It shows musical duration,
  tempo, meter, key signature, named tracks and note ranges; its options choose an all-tracks or
  per-track view, the pitch names and the keyboard width, and it provides horizontal zoom through the common zoom control without
  synthesizing or executing file content.
- `Archive` opens ZIP and ZIP64 containers, including JAR, APK, EPUB, office and package formats,
  in the common folder explorer, as quiet rows: glyph, name, a thin Arc bar of how well the member
  packed, its size and date in mono. The count under the title adds the packed and extracted
  weights; the information sheet gives a member's sizes, compression and CRC-32, and opens it.
  Opening an entry asynchronously prepares a bounded temporary
  copy, verifies its declared size and CRC-32, and opens it through the ordinary viewer registry.
  Closing the viewer returns to the archive. Stored and Deflate entries are decoded; encrypted entries,
  multi-disk archives, unsupported compression methods, oversized directories, and previews above
  256 MiB stop with an exact explanation. Nested archives use the same navigation history and
  retain their logical paths while their temporary sources remain owned by exploration.
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
  aligned to 64 KiB boundaries, uses 64-bit offsets, and its options set the row width and an
  independent scalar width, representation, and explicit Little/Big byte order; zoom sets the
  fixed-width font. Its
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
The document
shows a spinner once the active viewer has kept it waiting for 400 ms, keeps it for at least half
a second so that it never flickers, and leaves the previous document on screen meanwhile, so a
file that arrives quickly changes without any mark at all; switching viewers retires hidden
progressive work.

The window shows the document and nothing else. Every command is an entry of the lens, which
`Ctrl Space` opens: opening, exploring, closing and reloading, the files beside the open
one and the recent files and folders (`/`), the viewers the file can be seen in, find and its
options, full screen, the play modes, the explored folder's history and order, the theme, the
language and About, and every command of the viewer on screen under its name. The readings of the
open file are in the information sheet (`I`) and, faint, on the line at the foot of the document;
the viewer's own controls float over that foot while the pointer moves; the find bar floats at the
top on `Ctrl+F`; the files beside the open one and the viewer's side panel stand as cards beside
the work when asked for.

Without a file the window is its home: the Scope mark, large and faint, one line inviting a drop or
`Ctrl+O`, and under a hairline the last six files opened, each a quiet row with the faint glyph of
its kind, its name, and when it was opened. The row under the pointer rises, shows its folder and a
cross that removes it; `Delete` removes the chosen row and `Enter` opens it. "Clear…" under the list
removes the files that no longer exist or those opened more than a month ago, and, apart, clears
the whole history after asking. Older files are in the lens under `/`.

The application stores its palette, language, window state, recent files, bounded recent-folder
history, and remembered viewer choices in the user's application-data folder. It toggles full
screen with F11 — full screen hides every panel, and the viewer's controls still come with the
pointer — navigates the current folder with Left/Right, reloads with F5, opens with Ctrl+O,
and accepts one file dropped anywhere on the surface. The recent and current-folder lists show the
glyph of each file's default viewer; the current-folder heading opens the recent-folder menu and
returns to the last file viewed in the selected folder. Audio and video claim bare Left/Right for
ten-second seeks while active, and use Space for play/pause, M for mute, Up/Down for volume, and
Home for the start. An
installer may run `swagscope.exe --register-file-types`; normal launches never write the registry.

The image and video controls offer the same play-mode button, and the lens the same modes. They decide what follows a file
that has been played through: stop there, play it again, continue with the next file of the same
kind in its folder, or continue
with a random one that has not had its turn in that folder yet, every file once before any comes
again. Video and sound hand over when their stream ends, an animated picture when its animation
has run one cycle, and a still picture after the time per picture the image viewer's options set, which turns
a folder of pictures into a slideshow. The mode holds across files and sessions, the folder is
walked whatever the panel filter shows, and a file the mode brings up stays out of the history.

A lens entry, and the primary action of the information sheet, open the current file with the
operating system's registered default application. A right click names the same action and the
rest of what a file offers. On the line of readings at the foot of the document it answers for the
open file, and on a panel row for the file that row names: show it in the system file explorer, open it with the default application, hand it
to the system chooser of applications, or copy its full path or file name. A row of the history
offers two more, because the history is the one list the reader owns: drop that file from it, or
clear it entirely. Nothing here writes to the file, and external applications run in their own
processes.

## The viewer plugin API

`src/api/` is the whole surface a viewer is written against, published under the `Viewer`
namespace: `Viewer.Plugin` describes a viewer, `Viewer.Host` is what its creation callback
receives, `Viewer.Embedded` hosts a file through the same registry inside another viewer, and
`Viewer.SearchApi`, `Viewer.LifecycleApi`, `Viewer.BackgroundLoad`, `Viewer.LineCounter`, and the
search and clock helpers beside them are the support the host offers. Nothing else is available to a
viewer. No plugin receives `ViewerWindow`, its parts, its session structure, or application-private
callbacks, and the application never names a format.

Every viewer is written this way, the plain text one included. That is the point of the
arrangement: a viewer compiled into the executable and a viewer that will one day arrive as a
separate binary have the same shape, so the API is kept honest by every viewer already
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
document and cell its glyph lives in, an immutable smoke fixture, its selectors, whether its bytes
are text a reader may also want raw, an optional content probe, and an optional `attach` that
prepares the viewer for the application it joined.
A plugin publishes its embedded translations from `attach`, so its name reads in the reader's
language before any file is opened.

The creation callback calls `attachView` for its document and can create at most one action,
information, and command group through the host, plus one optional side panel: the window writes
the information and action groups on the faint line at the foot of the document, floats the
command group over it while the pointer moves, and names the side panel in the lens. The window
has no toolbar, so a viewer gives the lens a row for every command it offers through
`setLensSource`, answering a `Viewer.LensEntries` under its name. It declares
optional search and progressive-lifecycle behavior through `setSearch` and `setLifecycle`;
retained asynchronous notifications come only from `host.services()`. A viewer that plays its
file reports the end through `reportFinished` and acts on the answer, and one showing a still
picture reports it through `reportShown`, which is how the reader's play mode carries from one
file to the next without any viewer knowing the folder. Reject malformed content
with the exact decoder reason before attaching a view; the application presents every plugin
failure on the same error surface and owns cleanup of all contributed windows.

Playback controls belong to the viewer's command group. The image viewer creates a
`Viewer.PlaybackButton` there with `host.services().playback`; it shows the mode in force and
opens an option sheet with the play mode and the time per picture. The video viewer adds the same
rows to its own options through `PlaybackApi.addOptionRows`, beside its speed, sound track and
subtitles. The host stores the shared policy and handles file continuation; it creates no
playback button or options.

The fixture lives in `src/tests/datas`, is unique to that descriptor, and is a valid file the
plugin can open. The key is never translated or reused because remembered viewer choices persist
it. A built-in glyph remains a 24-unit cell in `datas/icons.svg` with a matching `ViewerIcons`
case in grid order; a separately built plugin would name a cell of the document it embeds itself.

Keep tests at `src/tests/viewer.<format>.test.swg`, fixtures in `src/tests/datas`, and image goldens
in `src/tests/goldens`. External fixtures record their source URLs, license, and hashes in
`datas/THIRDPARTY.md`.
Run a focused test with:

```text
swc tools/apps.swgs dm test swagscope --test-file viewer.<format>.test.swg
```

`swc tools/apps.swgs dm build swagscope` builds one executable containing all viewers and lets
the workspace publisher place its standard-module runtime dependencies beside it.

`swc tools/apps.swgs dm smoke swagscope` opens every plugin's registered fixture in order and
selects that plugin explicitly. It keeps progressive content visible long enough to exercise late
failures, waits while a viewer has no presentable content, and returns a nonzero exit code when a
fixture is missing or a plugin cannot open it.
