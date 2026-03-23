#global fileprivate

struct EventBase {}

struct MouseEvent
{
    using base: EventBase
}

interface IEvent {}

impl IEvent for EventBase {}
impl IEvent for MouseEvent {}

#test
{
    var evt: IEvent
    switch evt
    {
    case s32: // swc-expected-error {{sema_err_cannot_cast}}
        break
    }
}

#test
{
    var evt: IEvent
    switch evt
    {
    case MouseEvent as { x: s32 }: // swc-expected-error {{sema_err_switch_dynamic_case}}
        break
    }
}

#test
{
    var evt: IEvent
    switch evt
    {
    case EventBase:
        break
    case EventBase: // swc-expected-error {{sema_err_switch_case_duplicate}}
        break
    }
}

#test
{
    var evt: IEvent
    switch evt
    {
    case EventBase where true:
        break
    case EventBase: // swc-expected-error {{sema_err_switch_case_duplicate}}
        break
    }
}
