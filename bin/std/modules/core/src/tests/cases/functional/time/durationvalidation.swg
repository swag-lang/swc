#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    let negative = Swag.catchPanic(func||() { discard Time.Duration.fromSeconds(-0.5) })
    let infinite = Swag.catchPanic(func||() { discard Time.Duration.fromSeconds(Swag.F64.Inf) })
    let notANumber = Swag.catchPanic(func||() { discard Time.Duration.fromSeconds(Swag.F64.NaN) })

    Swag.require(negative.raised)
    Swag.require(infinite.raised)
    Swag.require(notANumber.raised)
}

#test
{
    let tooLarge = Swag.catchPanic(func||()
    {
        discard Time.Duration.fromMilliseconds(Swag.U64.Max).milliseconds()
    })
    Swag.require(tooLarge.raised)
}
