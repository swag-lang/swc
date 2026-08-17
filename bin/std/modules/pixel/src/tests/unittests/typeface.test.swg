#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// A rejected face must not try to destroy the uninitialized native face during failure cleanup.
#test
{
    const truncated: [4] u8 = [0, 1, 0, 0]
    discard catch TypeFace.create("pixel-test-truncated-font", truncated) as loadError
    @assert(loadError != null)
}
