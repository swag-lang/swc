using Core

// Converts a gain in decibels to a linear amplitude ratio.
//
// Values at or below `-100 dB` map to silence.
public func convertDBToPercent(dbVolume: f32)->f32
{
    if dbVolume > -100 do
        return Math.pow(10.0, dbVolume / 20.0)
    return 0.0
}

// Converts a linear amplitude ratio to decibels.
//
// Zero and negative inputs map to `-100 dB`.
public func convertPercentToDB(percentVolume: f32)->f32
{
    if percentVolume > 0.0 do
        return 20.0 * Math.log10(percentVolume)
    return -100.0
}
