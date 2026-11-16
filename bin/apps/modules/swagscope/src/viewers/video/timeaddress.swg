#global internal
#global namespace Viewers.Film

using Core

// Parses a source timestamp or a signed displacement in seconds. A negative result rejects it.
func parseTimeAddress(text: string, current, duration: f64)->f64
{
    let input = Latin1.trim(text)
    if not input.count do
        return -1
    let relative = input[0] == '+' or input[0] == '-'
    let number   = relative ? input[1 to] : input
    if not number.count do
        return -1
    let parts = Tokenize.split(number, ':'u8, removeEmpty: false)
    if parts.count > 3 or (relative and parts.count != 1) do
        return -1

    var seconds = 0.0'f64
    for part, index in parts
    {
        if not part.count do
            return -1
        let last = index + 1 == parts.count
        var dots: u32
        for byte in part
        {
            if byte == '.' and last do
                dots += 1
            elif byte < '0' or byte > '9' do
                return -1
        }

        if dots > 1 do
            return -1
        let value = catch StrConv.toF64(part) orelse -1
        if value < 0 or (index > 0 and value >= 60) do
            return -1
        seconds = seconds * 60 + value
    }

    let target = relative ? current + (input[0] == '-' ? -seconds : seconds) : seconds
    return target >= 0 and target <= duration ? target : -1
}
