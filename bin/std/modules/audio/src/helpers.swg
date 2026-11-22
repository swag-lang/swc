using Core

// Converts a gain in decibels to a linear amplitude ratio.
//
// Values at or below `-100 dB` map to silence. NaN remains NaN; positive decibel values may
// produce gains above one.
public func decibelsToLinearGain(decibels: f32)->f32
{
    if decibels <= -100 do
        return 0.0
    return Math.pow(10.0, decibels / 20.0)
}

// Converts a linear amplitude ratio to decibels.
//
// Zero and negative inputs map to `-100 dB`. NaN remains NaN.
public func linearGainToDecibels(gain: f32)->f32
{
    if gain <= 0.0 do
        return -100.0
    return 20.0 * Math.log10(gain)
}
