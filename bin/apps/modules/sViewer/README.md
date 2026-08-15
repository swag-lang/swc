# sViewer

sViewer is the fast universal viewer shipped with Swag. The executable owns only navigation,
drag and drop, file association, status, and plugin selection. Format code stays in optional
shared libraries and is loaded on first use.

## Startup contract

`plugins/index.viewer` is the only format registry read at startup. Each line maps a stable plugin
id and DLL to lowercase filename extensions:

```text
image|sviewer_image.dll|.png;.jpg;.gif
text|sviewer_text.dll|.txt;.md;.html;.cpp;.json
```

The host resolves an explicit extension and loads only that DLL. Unknown extensions remain
unsupported instead of being guessed as text. It resolves `s_viewer_plugin_create` and keeps the
library alive while plugin-owned windows exist. Adding formats therefore does not increase the
host's import set or initial UI construction.

## Shipped plugins

- `image` uses Pixel's decoders for BMP, GIF, ICO, JPEG, PNG, TGA, TIFF, and WebP. Its view adds
  pointer-centred zoom, pan, fit, actual size, rotation, a transparency grid, and GIF playback and
  seeking controls.
- `text` dispatches to separate plain-text, Markdown, HTML, and source-code renderers. Every source
  view uses `RichEdit`; Swag uses Gui's built-in lexer, while the plugin owns the lightweight lexer
  profiles for C/C++, C#, Java, JavaScript, TypeScript, Python, Rust, Go, JSON, XML, CSS, SQL, shell,
  PowerShell, Lua, Ruby, PHP, assembly, and configuration files. Markdown and HTML start in a fast
  offline semantic rendering and switch to their highlighted source in one click. Markdown covers
  headings, wrapped paragraphs, emphasis, links and images, task and ordered lists, quotes, fenced
  code, separators, and tables. HTML preserves document structure, preformatted text, nested lists,
  links, images, tables, details, and numeric entities while normalizing source indentation. Scripts,
  styles, embedded documents, and templates never execute.

The host navigates supported files in the current folder with Left/Right, reloads with F5, opens a
file with Ctrl+O, and accepts one file dropped anywhere on the surface. Image views also accept
`+`, `-`, Ctrl+0, F, R, and Space for playback.

Run `sViewer.exe --register-file-types` once from an installer or an explicit setup action to add
the shipped extensions to Windows. Normal launches never touch the registry.

## Adding a plugin

A plugin is a standalone shared-library module. It exports:

```swag
func sViewerPluginCreate(contentParent, commandParent: *Gui.Wnd, fileName: string,
                         apiVersion: u32, commands: *#null *Gui.Wnd)->#null *Gui.Wnd
```

Return null only for an unsupported ABI version. Put optional, compact controls in one group under
`commandParent` and return it through `commands`; the host merges it into its single command bar.
Decode failures belong inside a returned view so the host remains format-agnostic. sViewer is a
viewer, not an editor.

`swc tools/apps.swgs dm test sViewer` tests the host and every plugin module that declares tests as
an independent executable. This keeps the load boundary honest while covering renderer output and
dark-theme visual goldens through the same command used for the shipped application.
