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
func timeText(seconds: f64)->String
{
    return wholeTimeText(cast(u64) Math.max(Math.floor(seconds), 0))
}

// Formats a total duration, rounding a non-empty final fraction up so it never reads as zero.
func durationText(seconds: f64)->String
{
    return wholeTimeText(cast(u64) Math.max(Math.ceil(seconds), 0))
}

// Formats the current and total positions of a media transport.
func timeRangeText(current, duration: f64)->String
{
    return Format.toString("% / %", timeText(current), durationText(duration))
}
