#global public
#global namespace StrConv

// Returns the size `value`, in bytes, as a whole number of the largest 1024-based unit it reaches.
//
// The units are spelled `bytes` (`byte` for one), `KB`, `MB`, `GB` and `TB`, and the division
// truncates: 1536 bytes give `"1 KB"`. See [[Core.Format.byteSize]] for a size with fractional
// digits.
func toDisplaySize(value: u64)->String
{
    var size = value
    if size == 1 do
        return "1 byte"
    if size < 1024 do
        return Format.toString("% bytes", size)
    size /= 1024
    if size < 1024 do
        return Format.toString("% KB", size)
    size /= 1024
    if size < 1024 do
        return Format.toString("% MB", size)
    size /= 1024
    if size < 1024 do
        return Format.toString("% GB", size)
    size /= 1024
    return Format.toString("% TB", size)
}

// Returns the bit rate `value`, in bits per second, as a whole number of the largest 1000-based unit it reaches.
//
// The units are spelled `bps`, `Kbps`, `Mbps` and `Gbps`, and the division truncates.
func toDisplayBitrate(value: u64)->String
{
    var rate = value
    if rate < 1000 do
        return Format.toString("% bps", rate)
    rate /= 1000
    if rate < 1000 do
        return Format.toString("% Kbps", rate)
    rate /= 1000
    if rate < 1000 do
        return Format.toString("% Mbps", rate)
    rate /= 1000
    return Format.toString("% Gbps", rate)
}

// Returns the duration `ms`, in milliseconds, as days, hours, minutes and seconds, such as `"1d 2h 3m 4s"`.
//
// Leading units that are zero are left out, and the milliseconds are truncated.
func toDisplayDuration(ms: u64)->String
{
    let seconds = ms / 1000
    let days    = seconds / 86400
    let hours   = (seconds % 86400) / 3600
    let minutes = (seconds % 3600) / 60
    let secs    = seconds % 60

    if days > 0 do
        return Format.toString("%d %h %m %s", days, hours, minutes, secs)
    if hours > 0 do
        return Format.toString("%h %m %s", hours, minutes, secs)
    if minutes > 0 do
        return Format.toString("%m %s", minutes, secs)
    return Format.toString("%s", secs)
}
