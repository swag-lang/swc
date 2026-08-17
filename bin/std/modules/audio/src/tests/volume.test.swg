#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    audioAssertFloat(decibelsToLinearGain(0), 1)
    audioAssertFloat(decibelsToLinearGain(20), 10)
    audioAssertFloat(decibelsToLinearGain(-6.0206), 0.5, 0.0002)
    audioAssertFloat(decibelsToLinearGain(-100), 0)
    audioAssertFloat(decibelsToLinearGain(-120), 0)

    audioAssertFloat(linearGainToDecibels(1), 0)
    audioAssertFloat(linearGainToDecibels(10), 20)
    audioAssertFloat(linearGainToDecibels(0.5), -6.0206, 0.0002)
    audioAssertFloat(linearGainToDecibels(0), -100)
    audioAssertFloat(linearGainToDecibels(-0.1), -100)
}
