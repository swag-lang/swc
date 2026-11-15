#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func resolveOwnedPath(currentName, legacyName: string)->String
{
    let current = Path.combine(currentName)
    let legacy  = Path.combine(legacyName)

    if File.exists(current) do
        return current

    return File.exists(legacy) ? legacy : current
}

#test
{
    var allocator: Swag.Allocator
    allocator.setup()
    allocator.configure(false, false, false, false, false)
    let backing: Swag.IAllocator = &allocator
    let context = Swag.getContext()
    let originalAllocator = context.allocator
    context.allocator = backing
    defer context.allocator = originalAllocator

    scope
    {
        let existing = unwrap #curlocation.fileName
        let missing  = Path.combine(existing, ".missing")

        let current = resolveOwnedPath(missing, missing)
        discard Format.toString("allocation after return: %", 1)
        Swag.require(Path.equals(current, missing))

        let legacy = resolveOwnedPath(missing, existing)
        discard Format.toString("allocation after return: %", 2)
        Swag.require(Path.equals(legacy, existing))

        let early = resolveOwnedPath(existing, missing)
        discard Format.toString("allocation after return: %", 3)
        Swag.require(Path.equals(early, existing))
    }

    Swag.require(allocator.stats().countAlloc == 0)
}
