#global fileprivate

struct EventBase
{
    code: s32 = 10
}

struct MouseEvent
{
    using base: EventBase
    button: s32 = 2
}

struct KeyEvent
{
    using base: EventBase
    key: s32 = 7
}

interface IEvent {}

impl IEvent for EventBase {}
impl IEvent for MouseEvent {}
impl IEvent for KeyEvent {}

func dispatchEvent(evt: IEvent)->s32
{
    switch evt
    {
    case MouseEvent as ptr:
        return ptr.code + ptr.button
    case KeyEvent as ptr:
        return ptr.code + ptr.key
    case EventBase as ptr:
        return ptr.code
    }

    return -1
}

func classifyEvent(evt: IEvent)->s32
{
    switch evt
    {
    case MouseEvent:
        return 1
    case EventBase:
        return 2
    }

    return -1
}

func runEventDispatch()->bool
{
    var mouse: MouseEvent
    var key:   KeyEvent
    var base:  EventBase

    return dispatchEvent(cast(IEvent) mouse) == 12 and
           dispatchEvent(cast(IEvent) key) == 17 and
           dispatchEvent(cast(IEvent) base) == 10 and
           classifyEvent(cast(IEvent) mouse) == 1 and
           classifyEvent(cast(IEvent) base) == 2
}

#test
{
    const ok = #run runEventDispatch()
    #assert(ok)
}
