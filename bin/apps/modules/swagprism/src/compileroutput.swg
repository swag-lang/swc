#global internal

using Core, Gui, Pixel

// Keeps the compiler's RGB text runs separate from terminal control sequences.
struct CompilerOutput
{
    struct Run
    {
        start, end: u64
        style:      RichEditStyleRef
    }

    text:   String
    runs:   Array'Run
    colors: Array'Color
}

impl CompilerOutput
{
    // Style zero follows the theme; the other entries keep the colors sent by the compiler.
    mtd colorStyle(color: Color)->RichEditStyleRef
    {
        for i in .colors.count
        {
            if .colors[i] == color do
                return cast(RichEditStyleRef) (i + 1)
        }

        if .colors.count == 255 do
            return 0
        .colors.add(color)
        return cast(RichEditStyleRef) .colors.count
    }

    mtd parse(source: string)
    {
        .text.clear()
        .runs.clear()
        .colors.clear()

        let bytes = cast(const [..] u8) source
        var index = 0'u64
        var style: RichEditStyleRef
        while index < bytes.count
        {
            let start = index
            while index < bytes.count and bytes[index] != 27 do
                index += 1
            if index > start
            {
                let offset = .text.length
                .text.append(source[start until index])
                .runs.add({offset, .text.length, style})
            }

            if index == bytes.count do
                break
            index += 1
            if index == bytes.count do
                break
            if bytes[index] != '[' do
                continue
            index += 1

            // Only SGR changes text colors. Other complete or truncated controls carry no text.
            var params: Array'u32
            var value = 0'u32
            var valid = true
            while index < bytes.count and (bytes[index] < '@' or bytes[index] > '~')
            {
                let ch = bytes[index]
                if ch >= '0' and ch <= '9' do
                    value = Math.min(value * 10 + ch - '0', 65535)
                elif ch == ';'
                {
                    params.add(value)
                    value = 0
                }
                else do
                    valid = false
                index += 1
            }

            if index == bytes.count do
                break
            let command = bytes[index]
            index += 1
            if command != 'm' or not valid do
                continue
            params.add(value)

            var param = 0'u64
            while param < params.count
            {
                let code = params[param]
                if code == 0 or code == 39 do
                    style = 0
                elif code == 38 and param + 4 < params.count and params[param + 1] == 2
                {
                    if params[param + 2] <= 255 and params[param + 3] <= 255 and params[param + 4] <= 255 do
                        style = .colorStyle(Color.fromRgb(cast(u8) params[param + 2], cast(u8) params[param + 3], cast(u8) params[param + 4]))
                    param += 4
                }

                param += 1
            }
        }
    }

    mtd applyColors(ed: *RichEditCtrl)
    {
        for i in .colors.count
        {
            var color = .colors[i]
            color.ensureContrast(ed.themeColors().richEdit_Bk, 4.5)
            ed.styles[i + 1].colFg = color
        }
    }

    mtd show(editor: *RichEditCtrl)
    {
        editor.setText("")
        .applyColors(editor)
        let plain = .text.toString()
        for run in .runs do
            editor.addText(plain[run.start until run.end], run.style)
        editor.invalidate()
    }
}

impl IRichEditLexer for CompilerOutput
{
    mtd impl setup(ed: *RichEditCtrl) { discard ed }

    mtd impl setupTheme(ed: *RichEditCtrl) { .applyColors(ed) }

    mtd impl insertRune(ed: *RichEditCtrl, ch: rune)->bool
    {
        discard ed
        discard ch
        return false
    }

    // Styles were supplied with the text and survive subsequent layout passes.
    mtd impl compute(linePrev: *RichEditLine?, line: *RichEditLine, lineNext: *RichEditLine?)
    {
        discard linePrev
        discard line
        discard lineNext
    }
}
