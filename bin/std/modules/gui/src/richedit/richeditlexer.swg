public interface IRichEditLexer
{
    mtd setup(ed: #nonull *RichEditCtrl);
    mtd setupTheme(ed: #nonull *RichEditCtrl);
    mtd insertRune(ed: #nonull *RichEditCtrl, ch: rune)->bool;
    mtd compute(linePrev: #null *RichEditLine, line: #nonull *RichEditLine, lineNext: #null *RichEditLine);
}
