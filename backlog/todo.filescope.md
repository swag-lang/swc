# sFileScope Roadmap

This file is the product roadmap for sFileScope, measured against the viewers it competes with:
QuickLook and Seer on Windows, macOS Quick Look as the interaction reference, File Viewer Plus and
Universal Viewer as the "universal viewer" claim, Total Commander's Lister and its `wlx` plugin
ecosystem, and — on the binary side — HxD, ImHex, 010 Editor, CFF Explorer, PE-bear and Detect It
Easy. It is scoped to `bin/apps/modules/sFileScope` and to the `bin/std` facilities it depends on.

It holds intent only. A defect of this application is evidence and goes to a `findings.filescope.md`
beside this file, created the day it has an entry; a lead this application merely exposed goes to
the file of the unit that will fix it, [findings.gui.md](findings.gui.md) and its neighbours. Compiler
and language intent belongs in [todo.compiler.md](todo.compiler.md) and
[todo.language.md](todo.language.md), and a capability a `bin/std` module owns keeps its entry in
that module's file — this roadmap references those identifiers instead of restating them.
[README.md](README.md) has the whole layout.

Entries are ordered by decreasing value, not by decreasing effort. An entry disappears when it
ships; history lives in git, not here.

## Where sFileScope already stands

Worth stating, because it decides what is worth building next.

**Bounded streaming is the real differentiator.** A resident window opened at the requested offset,
64 KiB hex paging, asynchronous 256 KiB search chunks, an estimated scrollbar that keeps its
position as the estimate is refined, and a `revealMatch` in the contract so a viewer materializes
only the window containing a hit. The competing viewers load first and show second; a 4 GB file
opens here instantly and searches without being materialized. Nothing else in the category does
this.

**Read-only, offline, nothing executes.** No script, no embedded document, no style sheet fetch, no
network, and no registry write outside `--register-file-types`. QuickLook and Seer embed a browser
engine to render the same documents. For the actual use of a viewer — looking at a file before
trusting it — this is the right architecture, and it beats everyone but the dedicated forensic
tools.

**Hex, structure tree and one search over the same file.** the `Binary` viewer reads PE/PE32+, COFF,
`ar`, ELF, Mach-O and universal binaries, WebAssembly, ZIP and its derivatives, RIFF, sfnt and SCC
down to field name, decoded value, offset and meaning, and a hit inside a payload lands on the
structure that owns it. That normally takes CFF Explorer plus PE-bear plus a hex editor plus a ZIP
tool.

**Every viewer is in one executable.** The common request/result contract stays small, while direct
function bindings remove the ABI, dynamic loading, packaging, and version-skew failure modes. A
format viewer is now ordinary application code with the same tests and lifecycle as the window
that hosts it.

The gaps are elsewhere: nothing can be taken out of a view, the application is not reachable from
where files are actually selected, and the format table below is what a reader compares first.

---

## Tier A — What stops a reader from using it

### T-388 — Select-all in a streamed document silently means the resident window

- Measured, not assumed: the basic text view and the `Code` viewer both run on `RichEditCtrl`, which
  already selects with the mouse and the keyboard and already binds Ctrl+A and Ctrl+C — read-only
  guards none of that, and `viewerwindow.test.swg` asserts `editor.selectedText()` today. What the
  two views do not have is a *bound*: the editor holds one window of the file, so Ctrl+A over a
  4 GB log selects 256 KiB and Ctrl+C returns it with nothing said.
- Intent: a copy out of a partly resident document either carries the whole document or names what
  it carried, the way the `Hexadecimal` viewer names its own 1 MiB bound on the command itself.
- Complete when: select-all reaches the whole file or the command that copies it says how much of
  it is leaving, and a reader can tell the two apart before pasting.
- Note: the `Markdown` viewer now selects and copies too, and its select-all has exactly the same
  bound — it reaches the blocks the stream has materialized and no further — so whatever answer
  this entry settles on has to cover it.

### T-389 — Nothing appears in the Explorer preview pane

- Intent: the shipped viewers are reachable from where a file is selected. This is the whole reason
  QuickLook won its category: select, look, move on, without launching an application.
- Complete when: a registered preview handler renders the same views inside Explorer's preview
  pane, and `--register-file-types` installs it.
- Note: the handler hosts a view in a process it does not own, so the viewer request/result contract
  has to be usable without the application window. That constraint is worth checking before committing.
- Related: T-396, T-418

### T-393 — The file being viewed cannot be opened with its default application

- Intent: after looking at a file, the next action is always outside the viewer. Showing it in the
  file explorer, handing it to the system application chooser, and copying either its full path or
  its file name now answer from the context menu of the status bar and of both panel lists. What is
  still missing is opening it with its *default* application.
- Complete when: open-with-default joins that menu, and the actions a reader uses most are
  reachable from the action bar rather than only from a right click.

### T-394 — No zoom or text-size control

- Intent: the `Image` viewer zooms; no text-bearing view does. Ctrl+wheel and Ctrl+plus/minus do
  nothing in text, code, Markdown or HTML, so a dense source file is stuck at one size.
- Complete when: a shared zoom command changes text size in every basic and format-specific text view, is
  persisted, and leaves the streaming window arithmetic correct.

### T-395 — The hexadecimal view cannot search for a byte pattern

- Intent: the host search scans raw bytes for a literal string, which is what a text view needs and
  not what a hex reader wants. `4D 5A`, a wildcard run, or a little-endian scalar cannot be
  searched.
- Complete when: the `Hexadecimal` viewer contributes a byte-pattern query — hexadecimal pairs, wildcards, and
  the currently selected scalar type — routed through the same asynchronous host scan.

### T-396 — Explorer shows no thumbnail for a viewable file

- Intent: the image, SVG and Markdown views can produce a representative bitmap; Explorer asks for
  one and gets nothing.
- Complete when: a registered thumbnail provider renders a bounded preview for the formats that can
  produce one, with a size and timeout budget that never blocks a folder listing.
- Related: T-389

### T-397 — One document per window and per process

- Intent: every association launch starts another process with one document. There is no tab, no
  second document in the same window, and no side-by-side comparison of two files.
- Complete when: a running instance is reused, documents open as tabs, and two documents can be
  shown side by side.
- Related: T-233

### T-398 — A document cannot be printed

- Intent: a viewer that renders a document should be able to put it on paper, with the same
  pagination contract every other application uses rather than an application-local path.
- Complete when: text, code, Markdown, HTML and image views print through the GUI pagination and
  preview contract, with actual-size and fit-to-page.
- Related: T-047, T-234, T-236

---

## Tier B — Format coverage

The map below is what a reader compares before anything else, and it is where the "universal
viewer" claim is currently weakest. Read the `Today` column as:

- **full** — a dedicated view renders the format
- **structure** — the `Binary` viewer decodes the container into its field tree
- **signature** — identified, sized and weighed by entropy, nothing more
- **text** / **code** — falls into the basic text view or the code lexer
- **none** — only the hexadecimal fallback

`Entry` names the todo that closes the row, in this file or in the module's own file.

#### Text and documents

| Family | Extensions | Today | Missing | Entry |
| --- | --- | --- | --- | --- |
| Plain text | `.txt` `.ini` `.cfg` | full, streamed | — | — |
| Other encodings | UTF-16/32, Windows-1252 | full, detected and overridable | the multi-byte pages: Shift-JIS, GBK, EUC | — |
| Source code | registered extensions, common build/config names, and shebang scripts | full, lexer coloring | — | — |
| Markdown | `.md` `.markdown` | full | — | — |
| HTML | `.html` `.htm` `.xhtml` | full | advanced layout, SVG and CSS effects | [HTML roadmap](todo.html.md) |
| JSON, XML, YAML, TOML | `.json` `.xml` `.yaml` `.toml` | code | folding and value tree | — |
| Diff and patch | `.diff` `.patch` | text | hunk coloring and navigation | T-408 |
| Log | `.log` | text | level coloring, timestamps, tail | T-409 |
| Tabular text | `.csv` `.tsv` `.tab` | full up to 32 MiB, detected delimiter and quoting, fixed header | bounded streaming beyond 32 MiB | T-402 |
| PDF | `.pdf` | page rendering, editing and writing | encryption, annotations, shadings, scanned-image codecs | T-401, [todo.pdf.md](todo.pdf.md) |
| Office OOXML | `.docx` `.xlsx` `.pptx` | structure | readable text and sheets | T-407 |
| OpenDocument | `.odt` `.ods` `.odp` | structure | readable text and sheets | T-407 |
| Legacy Office | `.doc` `.xls` `.ppt` | signature | out of scope, see below | — |
| EPUB | `.epub` | structure | spine read through `HtmlView` | T-415 |
| RTF | `.rtf` | text | — | — |
| Mail | `.eml` `.msg` | none | — | — |
| Notebook | `.ipynb` | code | rendered cells | — |
| reStructuredText, AsciiDoc | `.rst` `.adoc` | text | — | — |

#### Images

| Family | Extensions | Today | Missing | Entry |
| --- | --- | --- | --- | --- |
| Raster | `.bmp` `.gif` `.ico` `.jpg` `.png` `.tga` `.tiff` `.webp` | full | — | — |
| Vector | `.svg` | full | clipping, masks, markers, symbols | T-189, T-191, T-192, T-326 |
| Metadata | EXIF, ICC, XMP | none | panel, orientation, color management | T-405 |
| Simple raster | `.qoi` `.pnm` `.ppm` | none | Pixel codec, only QOI is planned | T-055 |
| Modern codecs | `.avif` `.heic` `.jxl` | none | Pixel codec, HEIC unplanned | T-203, T-204 |
| High dynamic range | `.exr` `.hdr` | none | Pixel codec | T-207 |
| Layered | `.psd` `.xcf` | signature | Pixel importer | T-208 |
| GPU textures | `.dds` `.ktx2` | none | Pixel container | T-205, T-206 |
| Camera RAW | `.cr2` `.nef` `.arw` `.dng` | signature | embedded preview extraction | T-414 |

#### Audio and video

| Family | Extensions | Today | Missing | Entry |
| --- | --- | --- | --- | --- |
| WAV PCM and float | `.wav` | full, streamed | ADPCM | T-169 |
| Raw YUV4MPEG2 video | `.y4m` | full, silent, streamed by frame | the format carries no sound | — |
| Motion JPEG video | `.avi` `.mp4` `.m4v` `.mov` | full, seeked through sample tables; AVI plays its PCM sound and MP4/M4V/MOV their AAC-LC | the chroma layouts ffmpeg writes | T-426 |
| Compressed audio | `.mp3` `.flac` `.aac` `.ac3` `.eac3` | full, streamed | Ogg Vorbis, Opus, M4A | T-166, T-168 |
| Video containers | `.mp4` `.mkv` `.webm` `.mov` `.avi` | AVI structure; ISO-BMFF, Matroska and WebM signature | box and EBML trees | T-412 |
| Video playback | `.avi` `.mp4` `.m4v` `.mov` `.mkv` | Motion JPEG, uncompressed AVI, H.264, H.265 and MPEG-4 Part 2; container-supported sound with track selection | VP9, AV1, Opus, Vorbis, and WebM | T-420 |
| MIDI | `.mid` `.midi` | full, piano roll; structure alternative | playback and synthesis | — |

#### Binaries, containers and developer artifacts

| Family | Extensions | Today | Missing | Entry |
| --- | --- | --- | --- | --- |
| Windows images | `.exe` `.dll` `.sys` | structure, complete | — | — |
| COFF and archives | `.obj` `.lib` `.a` | structure | — | — |
| ELF and Mach-O | `.so` `.elf` `.dylib` | structure | — | — |
| WebAssembly | `.wasm` | structure | — | — |
| RIFF | `.wav` `.avi` | structure | — | — |
| Swag chunk container | `.scc` | structure, through `Core.Scc` | — | — |
| ZIP family | `.zip` `.jar` `.apk` `.vsix` | central directory only | open an entry inside the archive | T-403 |
| Other archives | `.7z` `.rar` `.tar` `.gz` `.xz` `.zst` `.cab` `.msi` | signature | listing, `tar`/`gzip` first | T-403 |
| TrueType fonts | `.ttf` `.ttc` | specimen and character map, first face | collection face selector | — |
| CFF and web fonts | `.otf` `.woff` `.woff2` | OTF specimen; WOFF/WOFF2 structure | WOFF containers | T-177, T-178 |
| Program databases | `.pdb` | signature | MSF stream directory, CodeView match | T-413 |
| Databases | `.sqlite` `.db` | signature | schema and table browse | T-410 |
| Certificates and keys | `.pem` `.der` `.crt` `.p12` | none | ASN.1 and X.509 decode | T-411 |
| Managed code | `.class` `.dex` | signature | — | — |
| Crash dumps | `.dmp` | none | — | — |
| Disk images | `.iso` `.vhd` | none | — | — |
| Unknown | any | signature, size, entropy | — | — |

### T-401 — A PDF the module cannot fully decode is shown as a failure, not as a page

- Intent: the module's own coverage gaps now live in [todo.pdf.md](todo.pdf.md), which is the
  roadmap for `std/pdf`. What stays here is the viewer's half: `PdfViewer` reports whatever
  `loadPage` or `render` failed with and shows nothing, so a document with one unsupported
  construct anywhere reads as a broken file rather than as a page with a gap in it.
- Complete when: the viewer draws the part of a page that decoded, states the construct it could
  not represent in localized text beside it rather than as a raw module error, and keeps page
  navigation working across a page it could only partly decode.
- Note: never execute an embedded action, and keep interactive form filling out of the viewer.
- Related: T-431, T-447

### T-402 — The table viewer is bounded to 32 MiB

- Intent: the table viewer detects comma, semicolon, tab or pipe separators, understands quoted
  fields and embedded line breaks, keeps its header visible, and virtualizes the GUI rows. It reads
  at most 32 MiB because the parsed source rows are still resident; the streamed basic-text viewer
  remains selectable for a larger file instead of the table exhausting memory.
- Complete when: source rows are themselves streamed through a bounded window and the row count is
  updated as the file is indexed, without weakening quoting across chunk boundaries.

### T-403 — An archive's entries cannot be opened

- Intent: a ZIP lists its central directory and stops; `tar`, `gzip`, `xz`, `zstd`, `7z`, `RAR`,
  `CAB` and `MSI` are only identified. Looking inside an archive is one of the two things a viewer
  is opened for.
- Complete when: a directory entry can be selected and its content handed to the matching viewer
  without extracting the whole archive, starting with the deflate and stored methods that
  `Core.Inflate` already covers, and with `tar`/`gzip` listing.

### T-405 — An image's metadata is not shown

- Intent: no EXIF, no ICC, no XMP anywhere. Orientation is therefore ignored, so a phone photograph
  displays rotated, and camera, exposure and capture date are invisible.
- Complete when: a metadata panel shows the decoded tags, EXIF orientation is applied on load, and
  an embedded ICC profile is at least reported.
- Related: T-052, T-198

### T-407 — Office and OpenDocument files stop at the ZIP structure

- Intent: `.docx` and `.odt` show a list of parts, which is right for an archive and useless for a
  document. Full fidelity is not the target; readable content is.
- Complete when: paragraphs, headings, lists and tables come out as a readable document through the
  existing reading column, and a spreadsheet's cells come out through the table view.
- Related: T-402, T-403

### T-408 — Diff and patch files read as plain text

- Intent: unified diffs are among the most frequently opened developer files and are the format
  where flat text costs the most.
- Complete when: hunks, added and removed lines and file headers are colored from the active theme,
  and per-file navigation moves between hunks.

### T-409 — Log files have no dedicated view

- Intent: a log is the archetypal huge file, which is where the streaming architecture already
  wins — but it opens at the beginning, uncolored, with no way to reach the end that matters.
- Complete when: severity levels and timestamps are recognized and colored, the view can open at the
  tail, and a level filter narrows what is shown without loading the file.

### T-410 — SQLite databases are only identified

- Intent: `.db` and `.sqlite` reach the entropy line. The schema and a bounded table read are what a
  reader wants, and the file format is documented and stable.
- Complete when: the schema, the tables and their row counts are listed, and a table is browsable
  through a bounded window over its pages.

### T-411 — Certificates and keys are not decoded

- Intent: `.pem`, `.der`, `.crt`, `.cer` and `.p12` show base64 or bytes. `Core.Crypto` and the
  binary viewer's structure model already give the two halves of what is needed.
- Complete when: an ASN.1 tree and a decoded X.509 summary — subject, issuer, validity, key, and
  extensions — are shown, with no validation claim of any kind.

### T-412 — MP4 and Matroska containers are only identified

- Intent: playback and structural inspection answer different questions. The `Video` viewer reads
  the supported picture and sound tracks, while the `Binary` alternative should expose the
  container itself like it already does for RIFF and the other structured formats.
- Complete when: the ISO-BMFF box tree, the Matroska EBML tree, and the track, codec, duration and
  resolution summaries are reported like any other structure.

### T-413 — A program database is only identified

- Intent: this repository writes PDBs. Reading one back with the same tool that inspects the image
  it belongs to is a capability the competition does not have, and it is a debugging asset here.
- Complete when: the MSF superblock, the stream directory, the named streams and the GUID/age that
  must match the image's CodeView record are reported by the `Binary` viewer.

### T-414 — Camera RAW files show nothing

- Intent: full RAW development is out of scope, but every RAW file embeds a JPEG preview, and
  showing it is most of the value at a fraction of the cost.
- Complete when: the embedded preview of the common TIFF-based RAW containers is extracted and
  displayed, with the metadata panel from T-405 beside it.
- Related: T-405

### T-420 — WebM and VP9/AV1 Matroska video cannot be played

- Intent: Matroska now plays H.264, H.265, or MPEG-4 Part 2 with selectable AAC-LC, AC-3, E-AC-3,
  FLAC, or MPEG Layer III tracks through a compact EBML block index. WebM, and Matroska streams
  carrying VP9, AV1, Opus, or Vorbis, remain unread.
  The container already retains timestamps, synchronization points, lacing, and payload offsets;
  what remains is picture and sound codec support rather than another container design.
- Complete when: the `Video` viewer shows the picture with transport, a seekable timeline and the
  frame position for VP9 or AV1 in WebM and Matroska, and the registry moves those extensions off
  the binary line for playback while T-412 keeps the structure reader available as a second
  viewer. Opus and Vorbis use `std/audio` and stay synchronized with the picture.
- Related: T-412, T-166, T-168

### T-571 — An unsupported picture codec hides sound tracks the application can play

- Intent: a container currently fails as a video document when its picture codec is unavailable,
  even if one of its sound tracks has a registered decoder. The measured library exposes this with
  its single RV40 film; future partial codec coverage must not turn supported audio into no output.
- Complete when: sFileScope offers a sound-only view for every decodable track when no picture
  track can be decoded, states that the picture is unavailable, and keeps ordinary video playback
  unchanged when both sides are supported.
- Related: T-568 in [todo.video.md](todo.video.md), T-562 in [todo.audio.md](todo.audio.md)

### T-415 — EPUB stops at the ZIP structure

- Intent: an EPUB is a spine of HTML documents, and the HTML view already renders them.
- Complete when: the spine order is read from the container manifest and its documents stream into
  the reading column in order.
- Related: T-403

---

## Tier C — Portability

### T-418 — File-type registration is Windows-only

- Intent: `Env.registerApplication`, `Env.associateFileExtension` and the shell integration entries
  above are the whole platform boundary; the viewers, streaming, and structure readers are portable.
- Complete when: desktop registration goes through whatever portable contract T-288 settles on.
- Related: T-266, T-288

---

## Out of scope

**Editing anything.** The read-only guarantee is the product. A viewer that can write is a different
application with a different risk profile, and the streaming window is designed around a file that
does not change under it.

**Format conversion and batch processing.** IrfanView and XnView own that ground, and it needs a
write path this application deliberately does not have.

**Legacy binary Office rendering.** `.doc`, `.xls` and `.ppt` are undocumented compound-document
formats whose fidelity nobody outside Microsoft reaches. The CFB structure is what the `Binary` viewer
can honestly show.

**Packer and protector identification.** Detect It Easy is built on a signature database that has to
be maintained against people actively evading it. Entropy and an honest signature line are the part
that does not rot.

**Hosted and cloud formats.** Reaching them means embedding third-party credentials in a compiler
repository.

**3D model preview.** Pixel is a 2D renderer, and a wireframe nobody trusts is not worth the
subsystem.
