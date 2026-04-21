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
    case MouseEvent as { x: s32 }: // swc-expected-error {{sema_err_switch_dynamic_case}}
        break
    }
}
