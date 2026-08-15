# sViewer

sViewer is the universal read-only viewer shipped with Swag. The executable owns navigation,
drag and drop, the action bar, the built-in text view, and lazy plugin selection. Format-specific
code stays in standalone shared libraries and enters the process only when selected.

## Viewer registry

`plugins/index.viewer` is the only plugin registry read at startup. Each line gives a stable id,
the label shown in the action-bar combo, the DLL, and one or more lowercase extensions:

```text
markdown|Markdown|sviewer_markdown.dll|.md;.markdown
image|Image|sviewer_image.dll|.png;.jpg;.gif
hex|Hexadecimal|sviewer_hex.dll|*
```

Several lines may claim the same extension. The combo lists format-specific plugins first,
`Basic text` next, then every plugin registered for `*`. The first choice is the default. Changing
the combo replaces only the current view; it does not reopen the window or reload unrelated DLLs.

Basic text belongs to the host rather than a plugin. It is available for every file, displays
valid UTF-8 as read-only fixed-width text, and is the source view for Markdown and HTML. It reads
small UTF-8 segments on demand and stays about two viewports ahead, so source files do not need to
fit in memory before their first screen appears. Binary content directs the reader to the
hexadecimal alternative instead of guessing an encoding.

## Shipped plugins

- `markdown` streams a centered reading column with separate typography and spacing for headings,
  prose, quotes, lists, fenced code, tables, rules, metadata, and display math. It supports task
  lists, autolinks, images, inline code, emphasis, highlight, strike-like secondary text, entities,
  and inline TeX notation for common symbols and operators. Display TeX uses Pixel's native math
  layout for fractions, roots, scripts, scalable delimiters, operators, matrices, cases, and aligned
  expressions. The renderer is offline and executes no embedded HTML or script.
- `html` streams document blocks into a centered page, keeps links explicit, and applies useful CSS
  from style sheets and inline declarations: tag, class, id and simple descendant selectors;
  foreground and background colors; font sizes, weights and styles; alignment; and body width.
  Head, script, style, template, and embedded-document content never executes.
- `image` uses Pixel decoders for BMP, GIF, ICO, JPEG, PNG, TGA, TIFF, and WebP. It provides zoom,
  pan, fit, actual size, rotation, transparency, and GIF playback and seeking.
- `sound` uses the Audio module to load and play PCM or float WAV files. It shows format metadata,
  a peak waveform, a live playhead, and Play/Pause/Stop controls.
- `hex` is available for every file. It pages through 64 KiB at a time and shows 64-bit offsets,
  sixteen hexadecimal bytes, and printable ASCII without loading a large file into memory.

The host navigates every file in the current folder with Left/Right, reloads with F5, opens with
Ctrl+O, and accepts one file dropped anywhere on the surface. Run
`sViewer.exe --register-file-types` from an installer or explicit setup action to register the
extensions declared by specialized plugins. Normal launches never write the registry.

## Adding a plugin

A plugin is a standalone shared-library module exporting:

```swag
func sViewerPluginCreate(contentParent, commandParent: *Gui.Wnd, fileName: string,
                         apiVersion: u32, commands: *#null *Gui.Wnd)->#null *Gui.Wnd
```

Return null only when the ABI version is not supported. Put optional compact controls in one group
under `commandParent` and return it through `commands`; return null through `commands` when the view
needs no actions. Decode errors belong inside a returned view so the host stays format-agnostic.

`swc tools/apps.swgs dm test sViewer` tests the host and every shipped plugin as an independent
executable. `swc tools/apps.swgs dm build sViewer` packages the DLLs, the registry, and the Audio
runtime beside the application.
