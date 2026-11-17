#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Errors

private func assertInvalidSourceOptions(options: SourceOptions)
{
    var failure: Swag.Error
    discard catch Source.open(options) as failure
    Swag.require(failure.value() is BadParameterError)
}

private func assertInvalidMonitorIndex(monitorIndex: u64)
{
    var failure: Swag.Error
    discard catch Source.openMonitor(monitorIndex) as failure
    Swag.require(failure.value() is BadParameterError)
}

// Shared dimension validation rejects invalid values before opening a display or allocating a frame.
#test
{
    assertInvalidSourceOptions({0, 0, 0, 1, false})
    assertInvalidSourceOptions({0, 0, 1, 0, false})
    assertInvalidSourceOptions({0, 0, -1, 1, false})
    assertInvalidSourceOptions({0, 0, 1, -1, false})
    assertInvalidSourceOptions({0, 0, Swag.S32.Max, 1, false})
    expect validateSourceOptions({0, 0, Swag.S32.Max / 4, 1, false})

    assertInvalidMonitorIndex(Swag.U64.Max)
}
