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
