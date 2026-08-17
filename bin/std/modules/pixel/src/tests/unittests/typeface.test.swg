#global if #command == Swag.CompilerCommand.Test

using Swag, Core

private func createNullableTypeFace(name: string, bytes: const [..] u8)->#null *TypeFace fail => try TypeFace.create(name, bytes)

// A rejected face must not try to destroy the uninitialized native face during failure cleanup.
#test
{
    const truncated: [4] u8 = [0, 1, 0, 0]
    let face = catch createNullableTypeFace("pixel-test-truncated-font", truncated) as loadError
    @assert(loadError != null)
    @assert(face == null)
}
