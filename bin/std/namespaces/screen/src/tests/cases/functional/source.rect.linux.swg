#global if #os == Swag.TargetOs.Linux
#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Errors

private func assertInvalidScreenRect(options: SourceOptions, desktopWidth, desktopHeight: u16)
{
    var failure: Swag.Error
    discard catch validateCaptureRect(options, desktopWidth, desktopHeight) as failure
    Swag.require(failure.value() is BadParameterError)
}

// X11 rectangle bounds are validated without a live display, including sums near s32 limits.
#test
{
    assertInvalidScreenRect({-1, 0, 1, 1, false}, 100, 50)
    assertInvalidScreenRect({0, -1, 1, 1, false}, 100, 50)
    assertInvalidScreenRect({99, 0, 2, 1, false}, 100, 50)
    assertInvalidScreenRect({0, 49, 1, 2, false}, 100, 50)

    // Coordinate plus extent exceeds s32, so the checked s64 sum must reject it rather than wrap.
    assertInvalidScreenRect({32767, 0, Swag.S32.Max, 1, false}, 65_535, 50)
    assertInvalidScreenRect({0, 32767, 1, Swag.S32.Max, false}, 100, 65_535)

    expect validateCaptureRect({99, 49, 1, 1, false}, 100, 50)
    expect validateCaptureRect({32767, 0, 1, 1, false}, 32_768, 50)
}
