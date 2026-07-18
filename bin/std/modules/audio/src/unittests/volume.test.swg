#global #if #command == Swag.CompilerCommand.Test
#global #[Swag.ExplicitNullability]
using Swag, Core

#test
{
    audioAssertFloat(convertDBToPercent(0), 1)
    audioAssertFloat(convertDBToPercent(20), 10)
    audioAssertFloat(convertDBToPercent(-6.0206), 0.5, 0.0002)
    audioAssertFloat(convertDBToPercent(-100), 0)
    audioAssertFloat(convertDBToPercent(-120), 0)

    audioAssertFloat(convertPercentToDB(1), 0)
    audioAssertFloat(convertPercentToDB(10), 20)
    audioAssertFloat(convertPercentToDB(0.5), -6.0206, 0.0002)
    audioAssertFloat(convertPercentToDB(0), -100)
    audioAssertFloat(convertPercentToDB(-0.1), -100)
}
