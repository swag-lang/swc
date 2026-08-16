# sFileScope

sFileScope is the universal read-only viewer shipped with Swag. The executable owns navigation,
drag and drop, the application action bar, the built-in text view, and lazy plugin selection.
Viewer selection and format-specific actions live in a separate viewer bar, so document tools do
not compete visually with Open, navigation, search, or the application theme. Format-specific code
stays in standalone shared libraries and enters the process only when selected.

## Viewer registry

`plugins/plugin.index.filescope` is the only plugin registry read at startup. Each line gives a stable id,
the label shown in the action-bar combo, the DLL, and one or more lowercase extensions:

```text
markdown|Markdown|plugin.markdown.dll|.md;.markdown
image|Image|plugin.image.dll|.png;.jpg;.gif;.svg
hex|Hexadecimal|plugin.hex.dll|*
```

Several lines may claim the same extension. The combo lists format-specific plugins first,
`Basic text` next, then every plugin registered for `*`. The first choice is the default. Changing
the combo reuses a view already opened for the current file or creates it on demand; it does not
reopen the window or reload unrelated DLLs.

Basic text belongs to the host rather than a plugin. It is available for every file, displays
valid UTF-8 as read-only fixed-width text, and is the source view for Markdown and HTML. It reads
small UTF-8 segments on demand and stays about two viewports ahead, so source files do not need to
fit in memory before their first screen appears. Binary content directs the reader to the
hexadecimal alternative instead of guessing an encoding.

## Shipped plugins

- `plugin.code` streams source with syntax coloring for Swag, C, C++, C#, Java, Kotlin,
  JavaScript, TypeScript, Go, Rust, Python, Ruby, shell, PowerShell, PHP, Lua, SQL, JSON, XML,
  CSS and preprocessors, YAML, TOML, configuration files, Swift, Dart, R, Perl, Visual Basic,
  shaders, CMake, and batch files. Swag uses the GUI's language lexer; its vocabulary is kept in
  step with the compiler's current keywords, intrinsics, compiler directives, and modifiers.
- `plugin.markdown` is a thin sFileScope adapter around the reusable GUI `MarkdownView`. It streams a
  themed reading column with separate typography and spacing for headings, prose, GFM alerts, nested
  lists and tasks, fenced code, aligned tables, rules, metadata, footnotes, references, and a table of
  contents. Emphasis, `***bold italic***`, highlight, strikeout, subscript, superscript, autolinks,
  entities, and inline or display TeX use the same renderer in every application. Pixel's native math
  layout handles fractions, roots, scripts, scalable delimiters, operators, matrices, cases, and aligned
  expressions. Reader, paper, and compact appearances can be combined with narrow, medium, wide, or
  fluid reading measures. The renderer is offline and executes no embedded HTML or script.
- `plugin.html` is a thin sFileScope adapter around the reusable GUI `HtmlView`. The control streams
  document blocks into a centered page, keeps links explicit, follows the active GUI palette, and
  applies useful CSS from style sheets and inline declarations: tag, class, id and simple descendant
  selectors; foreground and background colors; font sizes, weights and styles; alignment; and body
  width. Source colors are contrast-corrected against the active page ground. Head, script, style,
  template, and embedded-document content never executes.
- `plugin.image` uses Pixel decoders for BMP, GIF, ICO, JPEG, PNG, TGA, TIFF, and WebP, and Pixel's
  vector parser for SVG. It provides zoom, pan, fit, actual size, rotation, transparency, and GIF
  playback and seeking.
- `plugin.sound` uses the Audio module to load and play PCM or float WAV files. It shows format metadata,
  a peak waveform, a live playhead, and icon-only Play/Pause/Stop controls. Metadata and waveform
  decoding remain available when no playback device can be opened.
- `plugin.binary` takes a binary apart into the structure tree its own format declares, with the field
  name, the decoded value, the offset it was read at, and what it means side by side. Windows images
  (`PE32`/`PE32+`) are read down to their DOS and Rich headers, sections, data directories, imports and
  delayed imports, exports and forwarders, the resource tree with its decoded version block, the debug
  directory with the CodeView identity its symbol file must carry, relocations, thread-local storage,
  load configuration, the CLR header, and the appended signature. COFF objects, `ar` static and import
  libraries, ELF images with their program headers and dynamic section, Mach-O images and universal
  binaries, WebAssembly modules, ZIP archives and every container built on one, RIFF containers, and
  sfnt fonts each have their own reader; a Swag Chunk Container is read through the standard
  `Core.Scc` reader. A file no reader claims is still identified by signature, sized, and weighed by
  entropy. Ctrl+E opens or closes the whole tree, Ctrl+C copies the report as indented text, and a
  host search reveals the innermost structure covering the matching byte, so a hit inside a section's
  payload lands on that section.
- `plugin.hex` is available for every file. It pages through 64 KiB at a time and shows 64-bit offsets,
  hexadecimal bytes, and printable ASCII without loading a large file into memory. Its grouping field
  selects bytes or signed, unsigned, and floating-point values of 2, 4, or 8 bytes; navigation and
  selection snap to the chosen scalar and the inspector decodes that complete value in either endian.

Text, code, Markdown, and HTML views handle arrows, Home/End, Page Up/Page Down, and Space/Shift+Space
where appropriate. Their scrollbar represents an estimated full document while content is still
streaming and keeps its position as that estimate is refined. Forward keyboard navigation waits for
real content instead of chasing that estimate. Home, End, scrollbar jumps, and search open a bounded
resident window at the requested file offset, so distant navigation never materializes every preceding
byte. Ctrl+F opens the shared search field, Enter or F3 finds the next occurrence by scanning the file
in asynchronous 256 KiB chunks, and Escape restores the normal action bar.

The host keeps file type, name, size, and plugin-specific basic statistics in a persistent bottom
bar whose quieter surface is distinct from the document view. Its Dark/Light choice and native
window state (position, size, and maximized state) are stored in the user's application-data folder.
It navigates every file in the current folder with Left/Right, reloads with F5, opens with
Ctrl+O, and accepts one file dropped anywhere on the surface. Run
`sFileScope.exe --register-file-types` from an installer or explicit setup action to register the
extensions declared by specialized plugins. Normal launches never write the registry.

## Adding a plugin

A plugin is a standalone shared-library module exporting:

```swag
func sFileScopePluginCreate(contentParent, commandParent: *Gui.Wnd, fileName: string,
                         apiVersion: u32, commands: *#null *Gui.Wnd,
                         details: *Core.String,
                         revealMatch: *#null func(*Gui.Wnd, u64, string)->bool)->#null *Gui.Wnd
```

Return null only when the ABI version is not supported. Put optional compact controls in one group
under `commandParent` and return it through `commands`; return null through `commands` when the view
needs no actions. Return a concise format-specific summary through `details`; the host combines it
with the viewer type and file size. Decode errors belong inside a returned view so the host stays
format-agnostic. A searchable plugin returns a `revealMatch` callback that materializes and reveals
the bounded window containing the supplied byte offset; the host owns the asynchronous file scan.
Packaged plugin libraries and symbols use the `plugin.<what>` naming family.

`swc tools/apps.swgs dm test sFileScope` tests the host and every shipped plugin as an independent
executable. `swc tools/apps.swgs dm build sFileScope` packages the DLLs, the registry, and the Audio
runtime beside the application.
