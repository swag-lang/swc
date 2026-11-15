#global internal
#global namespace Viewers.Odf

using Core

// Converts ODF's physical units to reading points, without accepting expressions or URLs.
func points(value: string)->{value: f64, valid: bool}
{
    if value == "0" do
        return {0.0'f64, true}
    if value.count < 2 do
        return {0.0'f64, false}
    let unit   = value[value.count - 2 to]
    var factor = 0.0'f64
    switch unit
    {
    case "pt": factor = 1
    case "in": factor = 72
    case "cm": factor = 72 / 2.54
    case "mm": factor = 72 / 25.4
    case "pc": factor = 12
    case "px": factor = 0.75
    default:   return {0.0'f64, false}
    }

    let number = catch StrConv.toF64(value[until value.count - 2]) { return {0.0'f64, false} }
    let result = number * factor
    return {result, Math.isFinite(result) and Math.abs(result) <= 1584}
}

func rgb(value: string)->String
{
    if value.count == 7 and value[0] == '#'u8 and Package.isRgbHex(value[1 to]) do
        return String.from(value[1 to])
    return {}
}

func fontFamily(value: string)->String
{
    var name = Latin1.trim(value)
    if name.count >= 2 and ((name[0] == '\''u8 and name[name.count - 1] == '\''u8) or (name[0] == '"'u8 and name[name.count - 1] == '"'u8)) do
        name = name[1 until name.count - 1]
    if name.count > 256 do
        return {}
    for byte in name where byte < 128 and
                           not Latin1.isLetterOrDigit(byte) and
                           byte != ' 'u8 and
                           byte != '-'u8 and
                           byte != '.'u8 do
        return {}
    return String.from(name)
}
