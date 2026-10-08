#global if #command == Swag.CompilerCommand.Test
#global if WINDOWS
#global private

using Swag

var eventStatusPanicCount:     u32
var eventStatusBorrowLive:     bool
var eventStatusObservedBorrow: bool

func observeEventStatusPanic(_: string?, _: SourceCodeLocation)
{
    eventStatusPanicCount     += 1
    eventStatusObservedBorrow = eventStatusObservedBorrow or eventStatusBorrowLive
}

// Status operations retain the ordinary event's manual-reset and synchronous wait behavior.
#test
{
    var event: Sync.Event
    event.init(manual: true)
    let signaled = event.signalStatus()
    let waited   = event.waitStatus()
    let reset    = event.resetStatus()
    Swag.assert(signaled.isSuccess() and waited.isSuccess() and reset.isSuccess())
    expect signaled.raise()
    expect reset.raise()
    expect event.signalStatus().raise()
    expect event.waitStatus().raise()
}

// A genuine invalid-handle failure stays inert until the caller explicitly reports it.
// Error code zero still represents failure; catching a status releases its error storage.
#[Swag.Safety(.Expect, true)]
#test
{
    var allocator: Allocator
    allocator.setup()
    allocator.configure(false, false, false, false, false)
    defer allocator.release()
    let previous = Swag.getContext()
    defer Swag.setContext(previous)
    var context: Context
    let allocatorInterface = Swag.makeInterface(&allocator, #typeof(allocator), IAllocator)
    context.allocator        = allocatorInterface
    context.defaultAllocator = allocatorInterface
    context.errorAllocator.setCapacity(32, allocatorInterface)
    context.runtimeFlags = previous.runtimeFlags
    context.panic        = &observeEventStatusPanic
    Swag.setContext(context)
    defer context.releaseErrorStorage()

    eventStatusPanicCount     = 0
    eventStatusBorrowLive     = true
    eventStatusObservedBorrow = false
    let baseline          = allocator.stats().countAlloc
    var event: Sync.Event
    let signal            = event.signalStatus()
    let reset             = event.resetStatus()
    let wait              = event.waitStatus()
    let beforeReport      = allocator.stats().countAlloc
    let hooksBeforeReport = eventStatusPanicCount
    eventStatusBorrowLive = false

    var validCodes = true
    {
        catch signal.raise() as error
        if error is SystemError as value do
            validCodes = validCodes and value.errorID == 6
        else do
            validCodes = false
    }

    let afterSignalCatch = allocator.stats().countAlloc

    {
        catch reset.raise() as error
        if error is SystemError as value do
            validCodes = validCodes and value.errorID == 6
        else do
            validCodes = false
    }

    let afterResetCatch = allocator.stats().countAlloc

    {
        catch wait.raise() as error
        if error is SystemError as value do
            validCodes = validCodes and value.errorID == 6
        else do
            validCodes = false
    }

    let afterWaitCatch = allocator.stats().countAlloc

    {
        let noDetail = Sync.EventStatus{succeeded: false, errorCode: 0}
        catch noDetail.raise() as error
        if error is SystemError as value do
            validCodes = validCodes and value.errorID == 0 and value.message != null
        else do
            validCodes = false
    }

    let afterNoDetailCatch = allocator.stats().countAlloc

    context.panic = previous.panic

    Swag.assert(not signal.isSuccess() and not reset.isSuccess() and not wait.isSuccess())
    Swag.assert(beforeReport == baseline and hooksBeforeReport == 0)
    Swag.assert(validCodes, "event status must preserve the native failure codes")
    Swag.assert(afterSignalCatch == baseline and afterResetCatch == baseline and afterWaitCatch == baseline and afterNoDetailCatch == baseline, "caught event failures must release their storage")
    Swag.assert(eventStatusPanicCount == 0 and not eventStatusObservedBorrow)
}
