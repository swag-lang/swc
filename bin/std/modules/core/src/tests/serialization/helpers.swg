#global if #command == Swag.CompilerCommand.Test
#global namespace CoreTests

// Exercises decoding and releases a successful allocation; failure produces no result.
func(TR, T) readAndDelete(decoder: *Serialization.Decoder'T, input: const [..] u8) fail
{
    Memory.delete(try decoder.readAll'TR(input))
}
