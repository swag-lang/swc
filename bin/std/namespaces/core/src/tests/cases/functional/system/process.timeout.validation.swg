#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertInvalidProcessTimeout(timeout: Time.Duration)
{
    var process: Env.Process
    var error:   Swag.Error
    discard catch process.tryWaitForExit(timeout) as error
    Swag.require(error.value() is Errors.BadParameterError)
    Swag.require(Errors.message(error.value()) == "process timeout is outside the supported range")
}

// Timeout validation precedes any process-handle access and has no process side effects.
#test
{
    assertInvalidProcessTimeout(Time.Duration.fromSeconds(Swag.F64.Max))
}
