#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

// A checked native sentinel remains a failure even when GetLastError supplies no detail.
#test
{
    catch failWinError(0) as missingCode
    Swag.assert((missingCode is SystemError))
    let missing = cast #assume (*SystemError) missingCode
    Swag.assert(missing.errorID == 0)
    Swag.assert(missing.message == "the Windows operation failed without an error code")

    const InvalidHandleError = 6'u32
    catch failWinError(InvalidHandleError) as invalidHandle
    Swag.assert((invalidHandle is SystemError))
    let invalid = cast #assume (*SystemError) invalidHandle
    Swag.assert(invalid.errorID == InvalidHandleError)
    Swag.assert(invalid.message != null and invalid.message.count != 0)
}

// Native formatted messages use tracked storage, including spills, and captures retain it
// independently when the originating context releases that storage.
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
    context.errorAllocator.setCapacity(16, context.allocator)
    defer context.errorAllocator.release()
    Swag.setContext(context)

    const InvalidHandleError = 6'u32
    let baseline      = allocator.stats().countAlloc
    var messagesValid = true
    for 32
    {
        catch failWinError(InvalidHandleError) as error
        if error is SystemError as value do
            messagesValid = messagesValid and value.message != null and value.message.count != 0
        else do
            messagesValid = false
    }

    let afterHandled = allocator.stats().countAlloc
    context.errorAllocator.release()
    let afterRepeated = allocator.stats().countAlloc

    context.errorAllocator.setCapacity(16, context.allocator)
    var retainedValid:  bool
    var retainedBlocks: u64
    {
        catch failWinError(InvalidHandleError) as retained
        context.errorAllocator.release()
        retainedBlocks = allocator.stats().countAlloc
        if retained is SystemError as value do
            retainedValid = value.message != null and value.message.count != 0
    }

    let afterOwner = allocator.stats().countAlloc
    Swag.setContext(previous)

    Swag.assert(messagesValid and retainedValid)
    Swag.assert(afterHandled == baseline)
    Swag.assert(afterRepeated == baseline)
    Swag.assert(retainedBlocks > baseline)
    Swag.assert(afterOwner == baseline)
}
