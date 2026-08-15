#global internal

using Gui

struct PlainTextRenderer
{
}

impl PlainTextRenderer
{
    func configure(editor: *RichEditCtrl, wrapping: bool)
    {
        editor.setFlags(.ReadOnly | (wrapping ? RichEditFlags.WordWrap : .None))
    }
}
