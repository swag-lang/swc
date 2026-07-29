// Defines the operations supported by i rich edit lexer.
public interface IRichEditLexer
{
    // Performs the setup operation.
    mtd setup(ed: *RichEditCtrl)
    // Performs the setup theme operation.
    mtd setupTheme(ed: *RichEditCtrl)
    // Performs the insert rune operation.
    mtd insertRune(ed: *RichEditCtrl, ch: rune)->bool
    // Performs the compute operation.
    mtd compute(linePrev: #null *RichEditLine, line: *RichEditLine, lineNext: #null *RichEditLine)
}
