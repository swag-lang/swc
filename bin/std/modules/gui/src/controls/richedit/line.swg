using Core

// Stores one logical rich-text line and its per-rune style references.
#[Swag.Opaque]
public struct RichEditLine
{
    // One line of the document: its runes, the style of each rune, and the state the layout
    // and the lexer left on it. The control that owns the line maintains all of it.

    internal
    {
        chars:            Array'rune                 // Runes of the line, without its terminator.
        styles:           Array'RichEditStyleRef     // Style reference of each rune, same count as 'chars'.
        dirtyStyle:       bool                       // Whether the line must be lexed again.
        hidden:           u64                        // Fold depth hiding the line, zero when visible.
        drawingRect:      Math.Rectangle             // Last painted rectangle, in client space.
        lexerEndingState: s32                        // Lexer state at the end of the line, seeding the next one.
        lexerCptCmt:      s32                        // Depth of nested block comments at the end of the line.
        wordWrap:         bool                       // Whether the line was wrapped by the layout.
    }
}

impl RichEditLine
{
    #[Swag.Inline]
    {
        // Returns the number of runes and style references in this line.
        public mtd length() => .styles.count
        mtd isVisible()     => .hidden == 0
    }

    // Returns the rune at `index`.
    public mtd runeAt(index: u64)->rune => .chars[index]

    // Returns the syntax style assigned at `index`.
    public mtd styleAt(index: u64)->RichEditStyleRef => .styles[index]

    // Assigns `style` to the rune at `index`.
    public mtd setStyleAt(index: u64, style: RichEditStyleRef)
    {
        .styles[index] = style
    }

    // Returns the lexer-defined state carried from this line to the next one.
    public mtd lexerState()->s32 => .lexerEndingState

    // Replaces the lexer-defined state and returns whether it changed.
    public mtd setLexerState(state: s32)->bool
    {
        if .lexerEndingState == state do
            return false
        .lexerEndingState = state
        return true
    }

    // Requests syntax recomputation for this line.
    public mtd markStyleDirty()
    {
        .dirtyStyle = true
    }

    mtd resetInternal()
    {
        .dirtyStyle = true
        .wordWrap   = false
        .hidden     = 0
        .chars.clear()
        .styles.clear()
    }

    mtd insertRune(insIndex: u64, c: rune, txtStyle: u8)
    {
        .dirtyStyle = true
        .chars.insertAt(insIndex, c)
        .styles.insertAt(insIndex, txtStyle)
    }

    mtd insertRunes(insIndex: u64, src: RichEditLine, srcIndex, srcCount: u64)
    {
        .dirtyStyle = true
        var srcI = srcIndex
        for var i = insIndex; i < insIndex + srcCount; i += 1
        {
            .chars.insertAt(i, src.chars[srcI])
            .styles.insertAt(i, src.styles[srcI])
            srcI += 1
        }
    }

    mtd insertRunes(insIndex: u64, runes: const [..] rune, styles: const [..] u8)
    {
        .dirtyStyle = true
        var srcI = 0'u64
        for var i = insIndex; i < insIndex + runes.count; i += 1
        {
            .chars.insertAt(i, runes[srcI])
            .styles.insertAt(i, styles[srcI])
            srcI += 1
        }
    }

    mtd removeRunes(srcIndex, count: u64)
    {
        if !count do
            return
        .dirtyStyle = true
        .chars.remove(srcIndex, count)
        .styles.remove(srcIndex, count)
    }

    mtd setLength(l: u64)
    {
        .chars.resize(l)
        .styles.resize(l)
    }
}
