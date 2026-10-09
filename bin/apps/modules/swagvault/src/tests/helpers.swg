#global if #command == Swag.CompilerCommand.Test

// Fails with a volume error of `kind`, for the tests that check how a failure is reported.
func raiseVolumeError(kind: ErrorKind) fail
{
    fail volumeError(kind)
}
