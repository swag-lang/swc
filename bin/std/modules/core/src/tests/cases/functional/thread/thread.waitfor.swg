#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

struct ThreadWaitProbe
{
    event: Sync.Event
}

func blockThreadUntilSignaled(thread: const *Threading.Thread)
{
    let probe = cast(*ThreadWaitProbe, unwrap thread.userParam)
    probe.event.wait()
}

func emptyThread(_: const *Threading.Thread) {}

#test
{
    var probe: ThreadWaitProbe
    probe.event.init(manual: true)

    var thread: Threading.Thread
    expect thread.init(&blockThreadUntilSignaled, &probe)
    expect thread.start()

    Swag.require(not (expect thread.waitFor(Time.Duration.fromMilliseconds(0))))
    Swag.require(thread.isValid())

    probe.event.signal()
    Swag.require(expect thread.waitFor(Time.Duration.fromSeconds(1)))
    Swag.require(not thread.isValid())

    expect thread.init(&emptyThread)
    expect thread.start()
    Swag.require(expect thread.waitFor(Time.Duration.fromSeconds(1)))
}

#test
{
    var thread: Threading.Thread
    expect thread.init(&emptyThread)

    Swag.require(not (expect thread.waitFor(Time.Duration.fromMilliseconds(0))))
    expect thread.start()

    var secondStartFailure: Swag.Error
    discard catch thread.start() as secondStartFailure
    Swag.require(secondStartFailure.value() is Errors.BadParameterError)
    Swag.require(Errors.message(secondStartFailure.value()) == "thread already started")

    Swag.require(expect thread.waitFor(Time.Duration.fromSeconds(1)))
    Swag.require(not thread.isValid())
}
