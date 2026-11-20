using Core, Gui

// Each monitor has two glyphs with its index beside the open frame. The recording frame adds
// the record dot, so it stays distinct from both the still image and the generic screen video.
struct CaptureMonitorGlyph
{
    atlas: IconAtlas
    icons: IconSet
}

impl CaptureMonitorGlyph
{
    mtd setup(renderer: Pixel.IRenderer, number: u64)
    {
        const Digits = ["M0 1Q0 0 1.5 0T3 1v3q0 1-1.5 1T0 4z",
                        "M0.6 1l1.2-1v5",
                        "M0 1C0-0.3 3-0.3 3 1c0 1.25-3 2.75-3 4h3",
                        "M0 0h3L1.45 2.2C3.75 2.2 3.4 5 1.5 5 0.75 5 0.15 4.7 0 4.2",
                        "M2.4 5V0L0 3.3h3",
                        "M3 0H0v2.25c2.8-1 3 0.5 3 1.3C3 5 1 5.45 0 4.6",
                        "M2.8 0.3C0-1 0 2 0 3.4 0 5.5 3 5.6 3 3.65 3 2 0.6 2 0 3",
                        "M0 0h3L0.9 5",
                        "M1.5 2.3C-0.65 2.3-0.4 0 1.5 0s2.15 2.3 0 2.3C-0.7 2.3-0.6 5 1.5 5s2.2-2.7 0-2.7z",
                        "M0.2 4.7C3 6 3 3 3 1.6 3-0.5 0-0.6 0 1.35 0 3 2.4 3 3 2"]

        let text  = Format.toString("%", number)
        let step  = Math.min(4.25, 5.5 / cast(f32, text.count))
        let scale = step / 4.25
        let left  = 12.0 - (cast(f32, text.count - 1) * step + 3.0 * scale) * 0.5
        var numerals: String
        for digit, index in text.toSlice()
        {
            numerals += Format.toString("<path transform='translate(% 4.75) scale(% 1)' d='%' />",
                                        left + step * cast(f32, index), scale, Digits[digit - '0'u8])
        }

        const Screen = "<path d='M8 11H2.75Q1.5 11 1.5 9.75v-5.5Q1.5 3 2.75 3H8M5 11v2.5m-2.25 0h4.5'/>"
        const Record = "<circle cx='5' cy='7' r='1.3' fill='#ffffff' stroke='none'/>"
        var svg = String.from("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 48 24'>")
        for x, index in ["0", "24"]
        {
            svg += "<g transform='translate("
            svg += x
            svg += " 0) scale(1.5)' fill='none' stroke='#ffffff' stroke-width='1.4' stroke-linecap='round' stroke-linejoin='round'>"
            svg += Screen
            svg += "<g stroke-width='1.05'>"
            svg += numerals
            svg += "</g>"
            if index == 1 do
                svg += Record
            svg += "</g>"
        }
        svg += "</svg>"

        expect .atlas.setup(svg.toString())
        .icons.setup(renderer, &.atlas)
    }

    mtd opDrop() => .icons.free()
}

impl MainWnd
{
    mtd monitorGlyph(index: u64, recording: bool)->Icon
    {
        while .monitorGlyphs.count <= index
        {
            let number = .monitorGlyphs.count + 1
            let glyph  = .monitorGlyphs.addNew()
            glyph.setup(.app().renderer, number)
        }

        let glyph = unwrap .monitorGlyphs[index]
        return glyph.icons.icon(recording ? 1 : 0, themeActionIconSize(.themeMetrics()), .theme().res.atlasScale)
    }
}
