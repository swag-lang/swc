#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    let negative   = Swag.catchPanic(func||() { discard Time.Duration.fromSeconds(-0.5) })
    let infinite   = Swag.catchPanic(func||() { discard Time.Duration.fromSeconds(Swag.F64.Inf) })
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

#test
{
    var invalid = Time.Duration.fromSeconds(1)
    let seconds = cast(*f64, &invalid)
    seconds[] = -1

    let failure = Swag.catchPanic(func|&invalid|()
    {
        discard invalid.milliseconds()
    })
    Swag.require(failure.raised and failure.message() == "duration is invalid")
}

#test
{
    var infinite        = Time.Duration.fromSeconds(1)
    let infiniteSeconds = cast(*f64, &infinite)
    infiniteSeconds[] = Swag.F64.Inf
    let infiniteFailure = Swag.catchPanic(func|&infinite|()
    {
        discard infinite.milliseconds()
    })

    var notANumber = Time.Duration.fromSeconds(1)
    let nanSeconds = cast(*f64, &notANumber)
    nanSeconds[] = Swag.F64.NaN
    let nanFailure = Swag.catchPanic(func|&notANumber|()
    {
        discard notANumber.milliseconds()
    })

    Swag.require(infiniteFailure.raised and infiniteFailure.message() == "duration is invalid")
    Swag.require(nanFailure.raised and nanFailure.message() == "duration is invalid")
}
