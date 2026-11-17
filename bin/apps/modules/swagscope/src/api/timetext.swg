#global public
#global namespace Viewer

using Core

private func wholeTimeText(total: u64)->String
{
    let hours   = total / 3_600
    let minutes = total / 60 % 60
    let rest    = total % 60
    if hours do
        return Format.toString("%:%{02}:%{02}", hours, minutes, rest)
    return Format.toString("%:%{02}", total / 60, rest)
}

// Formats a media clock as m:ss, or h:mm:ss once an hour is reached.
//
// Every viewer that plays something reads its clock from here, so a film, a waveform, and a
// score all spell the same instant the same way.
func timeText(seconds: f64)->String => wholeTimeText(cast(u64, Math.max(Math.floor(seconds), 0)))

// Formats a total duration, rounding a non-empty final fraction up so it never reads as zero.
func durationText(seconds: f64)->String => wholeTimeText(cast(u64, Math.max(Math.ceil(seconds), 0)))

// Returns the words of a lens row going to `seconds`, typed as `typed`: the instant as the clock
// spells it, then what was typed when it spells it otherwise, so the row answers the query.
func timeJumpText(seconds: f64, typed: string)->String => jumpRowText(appStrings().lens_GoToTime, timeText(seconds).toString(), typed)

// Formats the current and total positions of a media transport.
func timeRangeText(current, duration: f64)->String => Format.toString("% / %", timeText(current), durationText(duration))

// Parses a media instant typed by a reader: `m:ss`, `h:mm:ss` or seconds, with an optional
// fraction on the last part, or a displacement in seconds from `current` after `+` or `-`.
// Returns the instant in seconds, or a negative value when the text names none within `duration`.
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
