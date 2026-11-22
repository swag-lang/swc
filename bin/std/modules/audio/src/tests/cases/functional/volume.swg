#global if #command == Swag.CompilerCommand.Test

using Swag, Core, Core.Errors

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

// NaN must reach the setters' finite-value validation instead of becoming silence.
#test
{
    const NotANumber = cast #bit (f32, 0x7FC0_0000'u32)
    Swag.require(not Math.isFinite(decibelsToLinearGain(NotANumber)))
    Swag.require(not Math.isFinite(linearGainToDecibels(NotANumber)))

    discard expect createNoSoundEngine()
    defer destroyEngine()

    var failure: Swag.Error
    discard catch setOutputVolumeDb(NotANumber) as failure
    Swag.require(failure.value() is Errors.BadParameterError)
}
