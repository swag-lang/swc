#global private

using Swag

func failOwnedInteger(value: s64) fail
{
    fail value
}

func ownedIntegerEquals(owner: const *Error, expected: s64)->bool
{
    catch owner.raise() as error
    if error is s64 as value do
        return value[] == expected
    return false
}

// Empty owners copy, reset and raise without manufacturing a failure.
#test
{
    var owner: Error
    Swag.assert(owner.isEmpty())
    var copied = owner
    owner.reset()
    owner.capture(null)
    catch copied.raise() as error
    Swag.assert(error == null)
    copied.reset()
    copied.reset()
    Swag.assert(copied.isEmpty())
}

// Capturing snapshots a dynamic value. Owner copies, moves and replacements retain their own
// references, and repeated raises preserve the type without consuming the saved failure.
#test
{
    var allocator: Allocator
    allocator.setup()
    allocator.configure(false, false, false, false, false)
    defer allocator.release()
    let previous = Swag.getContext()
    defer Swag.setContext(previous)
    var context: Context
    context.allocator        = Swag.makeInterface(&allocator, #typeof(allocator), IAllocator)
    context.defaultAllocator = context.allocator
    context.runtimeFlags     = previous.runtimeFlags
    context.errorAllocator.setCapacity(32, context.allocator)
    Swag.setContext(context)
    defer context.releaseErrorStorage()

    let baseline = allocator.stats().countAlloc
    var valid    = true
    for 64
    {
        var owner: Error
        {
            catch failOwnedInteger(41) as error
            owner.capture(error)
        }
        owner = owner
        var copied = owner
        var moved  = #move copied
        {
            catch failOwnedInteger(73) as error
            owner.capture(error)
        }
        valid = valid and ownedIntegerEquals(&owner, 73) and ownedIntegerEquals(&moved, 41)
        {
            var dropped = owner
            owner.capture(null)
            valid = valid and
                    owner.isEmpty() and
                    ownedIntegerEquals(&dropped, 73) and
                    ownedIntegerEquals(&moved, 41)
        }
        moved.reset()
        moved.reset()
        valid = valid and allocator.stats().countAlloc == baseline
    }
    let finalCount = allocator.stats().countAlloc
    Swag.assert(valid)
    Swag.assert(finalCount == baseline)
}
