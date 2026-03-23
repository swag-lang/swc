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

struct MouseWheelEvent
{
    using mouse: MouseEvent
    delta: s32 = 3
}

struct KeyEvent
{
    using base: EventBase
    key: s32 = 7
}

interface IEvent {}

impl IEvent for EventBase {}
impl IEvent for MouseEvent {}
impl IEvent for MouseWheelEvent {}
impl IEvent for KeyEvent {}

func dispatchEvent(evt: IEvent)->s32
{
    switch evt
    {
    case MouseWheelEvent as ptr where ptr.delta == 3:
        return ptr.code + ptr.button + ptr.delta
    case MouseEvent as ptr where ptr.button == 2:
        return ptr.code + ptr.button
    case KeyEvent as ptr:
        return ptr.code + ptr.key
    case EventBase as ptr:
        return ptr.code
    default:
        return -1
    }
}

func classifyEvent(evt: IEvent)->s32
{
    switch evt
    {
    case MouseWheelEvent, MouseEvent:
        return 1
    case KeyEvent, EventBase:
        return 2
    default:
        return -1
    }
}

func fallbackAfterWhere(evt: IEvent)->s32
{
    switch evt
    {
    case EventBase as ptr where ptr.code == 99:
        return -99
    case EventBase as ptr:
        return ptr.code
    default:
        return -1
    }
}

func fallthroughToBase(evt: IEvent)->s32
{
    switch evt
    {
    case MouseEvent as ptr where ptr.button == 2:
        fallthrough
    case EventBase as ptr:
        return ptr.code
    default:
        return -1
    }
}

func classifyNil(evt: IEvent)->s32
{
    switch evt
    {
    case EventBase:
        return 1
    default:
        return 0
    }
}

func runInterfaceSwitch()->bool
{
    var wheel: MouseWheelEvent
    var mouse: MouseEvent
    var key:   KeyEvent
    var base:  EventBase
    var empty: IEvent

    return dispatchEvent(cast(IEvent) wheel) == 15 and
           dispatchEvent(cast(IEvent) mouse) == 12 and
           dispatchEvent(cast(IEvent) key) == 17 and
           dispatchEvent(cast(IEvent) base) == 10 and
           classifyEvent(cast(IEvent) wheel) == 1 and
           classifyEvent(cast(IEvent) mouse) == 1 and
           classifyEvent(cast(IEvent) key) == 2 and
           classifyEvent(cast(IEvent) base) == 2 and
           fallbackAfterWhere(cast(IEvent) mouse) == 10 and
           fallthroughToBase(cast(IEvent) mouse) == 10 and
           fallthroughToBase(cast(IEvent) key) == 10 and
           classifyNil(empty) == 0
}

#test
{
    const ok = #run runInterfaceSwitch()
    #assert(ok)
}
