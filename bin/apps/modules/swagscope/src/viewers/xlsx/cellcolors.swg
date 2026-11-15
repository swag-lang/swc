#global internal
#global namespace Viewers.Xlsx

using Core, Pixel

// Spreadsheet theme order differs from the DrawingML color-scheme order.
private const ThemeOrder    = [1'u32, 0, 3, 2, 4, 5, 6, 7, 8, 9, 10, 11]
private const IndexedColors = [
    0x000000'u32, 0xFFFFFF, 0xFF0000, 0x00FF00, 0x0000FF, 0xFFFF00, 0xFF00FF, 0x00FFFF,
    0x000000, 0xFFFFFF, 0xFF0000, 0x00FF00, 0x0000FF, 0xFFFF00, 0xFF00FF, 0x00FFFF,
    0x800000, 0x008000, 0x000080, 0x808000, 0x800080, 0x008080, 0xC0C0C0, 0x808080,
    0x9999FF, 0x993366, 0xFFFFCC, 0xCCFFFF, 0x660066, 0xFF8080, 0x0066CC, 0xCCCCCC,
    0x000080, 0xFF00FF, 0xFFFF00, 0x00FFFF, 0x800080, 0x800000, 0x008080, 0x0000FF,
    0x00CCFF, 0xCCFFFF, 0xCCFFCC, 0xFFFF99, 0x99CCFF, 0xFF99CC, 0xCC99FF, 0xFFCC99,
    0x3366FF, 0x33CCCC, 0x99CC00, 0xFFCC00, 0xFF9900, 0xFF6600, 0x666699, 0x969696,
    0x003366, 0x339966, 0x003300, 0x333300, 0x993300, 0x993366, 0x333399, 0x333333]

struct CellColors
{
    theme:   Package.OfficeTheme
    indexed: [66] u32
    valid:   [66] bool
}

impl CellColors
{
    func parse(source: string, theme: const *Package.OfficeTheme)->CellColors fail
    {
        var result: #returntype
        result.theme = theme[]
        for rgb, index in IndexedColors do
            result.indexed[index] = 0xFF000000 | rgb
        for index in result.valid.count do
            result.valid[index] = true
        result.indexed[64] = 0xFF000000
        result.indexed[65] = 0xFFFFFFFF
        var scan      = Package.Scanner.create(source)
        var token: Package.Token
        var inIndexed = false
        var index     = 0'u64
        while scan.next(&token)
        {
            if token.kind == .Start and token.isElement("indexedColors")
            {
                inIndexed = not token.empty
            }
            elif token.kind == .End and token.isElement("indexedColors")
            {
                inIndexed = false
            }
            elif inIndexed and token.kind == .Start and token.isElement("rgbColor")
            {
                if index >= 64 do
                    fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                let color = result.color(&token)
                result.valid[index] = color.valid
                if color.valid do
                    result.indexed[index] = color.argb
                index += 1
            }
        }

        if scan.damaged do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        return result
    }

    mtd const color(token: const *Package.Token, fallback = 0xFF000000'u32)->{argb: u32, valid: bool}
    {
        var result: #returntype = {fallback, true}
        if let value = token.attribute("rgb")
        {
            for byte in value where not Latin1.isHexDigit(byte) do
                return {fallback, false}
            var rgb = value
            if value.count == 8 do
                rgb = value[2 to]
            if not Package.isRgbHex(rgb) do
                return {fallback, false}
            result.argb = 0xFF000000 | (catch StrConv.toU32(Format.toString("0x%", rgb)) orelse 0)
        }
        elif let value = token.attribute("theme")
        {
            let index = catch StrConv.toU64(value) orelse Swag.U64.Max
            if index >= ThemeOrder.count do
                return {fallback, false}
            let rgb = .theme.colors[ThemeOrder[index]]
            if not Package.isRgbHex(rgb.toString()) do
                return {fallback, false}
            result.argb = 0xFF000000 | (catch StrConv.toU32(Format.toString("0x%", rgb)) orelse 0)
        }
        elif let value = token.attribute("indexed")
        {
            let index = catch StrConv.toU64(value) orelse Swag.U64.Max
            if index >= .indexed.count do
                return {fallback, false}
            result.argb  = .indexed[index]
            result.valid = .valid[index]
        }

        if let value = token.attribute("tint")
        {
            let tint = catch StrConv.toF64(value) { return {fallback, false} }
            if not Math.isFinite(tint) or tint < -1 or tint > 1 do
                return {fallback, false}
            if tint != 0
            {
                let color = Color.fromArgb(result.argb)
                let hsl   = color.toHsl()

                // Spreadsheet tints transform luminance on the Office HLS scale (0..240).
                let luminance = Math.round(hsl.l * 240)
                let adjusted  = tint < 0 ? luminance * (1 + tint) : luminance * (1 - tint) + 240 * tint
                if hsl.s == 0
                {
                    let gray = cast(u8, Math.round(adjusted / 240 * 255))
                    result.argb = Color.fromRgb(gray, gray, gray).argb
                }
                else
                {
                    result.argb = Color.fromHsl(hsl.h, hsl.s, cast(f32, adjusted / 240)).argb
                }
            }
        }

        return result
    }
}
