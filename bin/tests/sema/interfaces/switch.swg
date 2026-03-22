// @BUG switching on interface-typed values is currently rejected, but std/examples rely on IEvent-style interface dispatch patterns.
#global skip
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

#test
{
    var mouse: MouseEvent
    var key:   KeyEvent
    discard dispatchEvent(cast(IEvent) mouse)
    discard dispatchEvent(cast(IEvent) key)
}
