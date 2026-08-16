// Assigns syntax styles to rich-editor lines and optionally handles inserted runes.
public interface IRichEditLexer
{
    // Initializes lexer-owned state and style mappings for `ed`.
    mtd setup(ed: *RichEditCtrl)

    // Reapplies lexer-specific colors after the editor theme changes.
    mtd setupTheme(ed: *RichEditCtrl)

    // Handles `ch` before the editor's default insertion; returns `true` when consumed.
    mtd insertRune(ed: *RichEditCtrl, ch: rune)->bool

    // Recomputes lexical state and styles for `line`, with adjacent-line context.
    mtd compute(linePrev: #null *RichEditLine, line: *RichEditLine, lineNext: #null *RichEditLine)
}
