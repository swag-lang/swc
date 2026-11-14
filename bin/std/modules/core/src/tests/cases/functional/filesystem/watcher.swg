#global if #command == Swag.CompilerCommand.Test
#global private

#test
{
    var options: Directory.WatchOptions
    options.filter = cast(Directory.WatchFilter, 0)

    var errOutcome: Swag.Error
    discard catch Directory.watch(".", options) as errOutcome
    Swag.require(errOutcome.value() is Errors.BadParameterError)
}

#test
{
    var options: Directory.WatchOptions
    options.filter = cast(Directory.WatchFilter, 0x80000000'u32)

    var errOutcome: Swag.Error
    discard catch Directory.watch(".", options) as errOutcome
    Swag.require(errOutcome.value() is Errors.BadParameterError)
}
