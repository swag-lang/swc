#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A standalone TypeFace still owns its dynamically allocated cache/source name.
#test
{
    var allocator: Swag.Allocator
    allocator.setup()
    defer allocator.releaseAll()

    let context = Swag.getContext()
    let previousAllocator = context.allocator
    defer context.allocator = previousAllocator
    let testAllocator: IAllocator = &allocator
    context.allocator = testAllocator

    let baseline = allocator.stats().countAlloc
    var typeface: TypeFace
    typeface.fullName = "pixel test typeface name longer than inline String storage"
    Swag.require(allocator.stats().countAlloc > baseline)

    Swag.drop(&typeface, 1)
    Swag.init(&typeface, 1)
    Swag.require(allocator.stats().countAlloc == baseline)
}
