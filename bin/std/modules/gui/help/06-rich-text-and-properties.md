# Rich text and properties

[[Gui.RichEditCtrl]] provides multi-line editing, selections, undoable commands,
lexical styling, and viewport management. Its cursor and selection values use
text positions defined by the rich-edit model rather than Pixel coordinates.

Keep model operations separate from painting:

1. Apply text or selection commands.
2. Let the control update layout and undo state.
3. Invalidate the affected view.
4. Respond to semantic notifications outside the editor.

The property system builds editors from reflected values and metadata.
[[Gui.Properties]] describes a property source,
[[Gui.PropertiesItem]] represents one row, and [[Gui.PropertiesCtrl]] presents
the editable tree. Attributes such as category, display name, and description
keep domain-specific labels beside the data model.

Use the provided undo layer when edits must be reversible. Validation belongs at
the model boundary: the editor can report invalid input without committing a
partially converted value.

## Markdown documents

[[Gui.Markdown.View]] is the reusable, read-only Markdown document widget. Use
[[Gui.Markdown.View.createText]] for an in-memory document and
[[Gui.Markdown.View.createFile]] to stream UTF-8 source without blocking the
application on the whole file. Both forms use [[Gui.Markdown.Style]] for reading
measure, insets, and type sizes; [[Gui.Markdown.Style.theme]] is the standard
theme-following style.

```swag
let markdown = Markdown.View.createFile(parent, fileName, Markdown.Style.theme())
markdown.sigLinkActivated += func(view, url)
{
    discard view
    Env.openUrl(url)
}
```

The renderer supports GFM headings, lists, tasks, fenced code, tables,
autolinks, reference links, alerts, footnotes, metadata, and thematic rules,
plus Typora-style highlight, subscript, superscript, table of contents, and TeX
delimiters. Inline and display TeX are laid out by [[Pixel.MathExpression]];
the widget does not substitute approximate Unicode glyphs.

Inline HTML uses the HTML parser and translates phrasing elements into rich text:
links, bold and emphasis, deleted text, code, highlighting, subscript, superscript,
and line breaks retain their meaning. Other inline elements contribute their child
text without adding layout. An inline `img` is a textual image link, as is Markdown
`![alt](url)` syntax.

A line beginning with a layout-bearing HTML element starts an HTML block hosted by
[[Gui.HtmlView]]. Its supported CSS and layout rules apply inside that block. Local
images resolve against the streamed Markdown file's directory; `data:` images can
also render. Remote images are not fetched, and scripts never execute. Unsupported
HTML and CSS follow the HTML engine's fallback rules; this is an offline document
viewer, with no browser scripting or network resource loader.

Every surface, rule, link, selection, notice, and text color comes from the
active GUI theme. A theme change relayouts the document and all mathematical
expressions without rebuilding the source model.
Changing the language refreshes alert titles in existing and progressively loaded
blocks. The document's authored text stays unchanged.
