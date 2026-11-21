#global private

using Swag

func failOwnedInteger(value: s64) fail
{
    fail value
}

func ownedIntegerEquals(owner: const *Error, expected: s64)->bool
{
    var errorOutcome: Swag.Error
    catch owner.raise() as errorOutcome
    let error = errorOutcome.value()
    if error is s64 as value do
        return value[] == expected
    return false
}

private var reentrantCaptureEnabled = false
private var reentrantReplacementDrops = 0

private struct ReentrantReplacementPayload {}

impl ReentrantReplacementPayload
{
    mtd opDrop() { reentrantReplacementDrops += 1 }
}

private func failReentrantReplacement() fail
{
    fail ReentrantReplacementPayload{}
}

private struct ReentrantCapturePayload
{
    owner: *Error?
}

impl ReentrantCapturePayload
{
    mtd opDrop()
    {
        if reentrantCaptureEnabled
        {
            reentrantCaptureEnabled = false
            let owner = unwrap .owner
            catch failReentrantReplacement() { owner.capture(Swag.err) }
        }
    }
}

private func failReentrantCapture(owner: *Error) fail
{
    fail ReentrantCapturePayload{owner}
}

// Empty owners copy, reset and raise without manufacturing a failure.
#test
{
    var owner: Error
    Swag.require(owner.isEmpty())
    var copied = owner
    owner.reset()
    owner.capture(null)
    var errorOutcome: Swag.Error
    catch copied.raise() as errorOutcome
    let error = errorOutcome.value()
    Swag.require(error == null)
    copied.reset()
    copied.reset()
    Swag.require(copied.isEmpty())
}

// Resetting detaches the current record before dropping its payload. A capture performed by that
// payload's destructor is a later owner mutation and must remain retained after reset returns.
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

    let baseline = allocator.stats().countAlloc
    var owner: Error
    reentrantReplacementDrops = 0
    reentrantCaptureEnabled = false
    scope
    {
        catch failReentrantCapture(&owner) { owner.capture(Swag.err) }
    }
    reentrantCaptureEnabled = true
    owner.reset()
    let replacement = owner.value()
    let keptReplacement = replacement is ReentrantReplacementPayload
    owner.reset()

    scope
    {
        catch failReentrantCapture(&owner) { owner.capture(Swag.err) }
    }
    reentrantCaptureEnabled = true
    scope
    {
        catch failOwnedInteger(42) { owner.capture(Swag.err) }
    }
    let captured = owner.value()
    let keptReentrantCapture = captured is ReentrantReplacementPayload
    owner.reset()
    let isEmpty = owner.isEmpty()
    let drops = reentrantReplacementDrops
    context.releaseErrorStorage()
    Swag.require(keptReplacement)
    Swag.require(keptReentrantCapture)
    Swag.require(isEmpty)
    Swag.require(drops == 4)
    Swag.require(allocator.stats().countAlloc == baseline)
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
        scope
        {
            catch failOwnedInteger(41) { owner.capture(Swag.err) }
        }
        owner = owner
        var copied = owner
        var moved  = #move copied
        scope
        {
            catch failOwnedInteger(73) { owner.capture(Swag.err) }
        }
        valid = valid and ownedIntegerEquals(&owner, 73) and ownedIntegerEquals(&moved, 41)
        scope
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
    Swag.require(valid)
    Swag.require(finalCount == baseline)
}
