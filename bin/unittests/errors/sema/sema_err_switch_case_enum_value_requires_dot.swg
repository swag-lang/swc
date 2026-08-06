#global private

enum State
{
    Idle,
    Running
}

#test
{
    let state = State.Idle
    switch state
    {
    case Idle:     // swc-expected-error {{sema_err_switch_case_enum_value_requires_dot}}
        break
    case .Running:
        break
    }
}
