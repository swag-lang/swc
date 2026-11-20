#global private

enum State
{
    Ready
    Running
    Done
}

func missingValue(state: State)
{
    switch state     // swc-expected-error {{sema_err_switch_complete_enum_not_exhaustive}}
    {
    case .Ready, .Running: break
    }
}

func guardedValue(state: State, guard: bool)
{
    switch state     // swc-expected-error {{sema_err_switch_complete_enum_not_exhaustive}}
    {
    case .Ready, .Running:  break
    case .Done where guard: break
    }
}

func exclusiveUpperBound(state: State)
{
    switch state     // swc-expected-error {{sema_err_switch_complete_enum_not_exhaustive}}
    {
    case .Ready until .Done: break
    }
}

enum FloatState: f32
{
    Number = 1.0
    NaN    = Swag.F32.NaN
}

func unorderedFloat(state: FloatState)
{
    switch state     // swc-expected-error {{sema_err_switch_complete_enum_not_exhaustive}}
    {
    case .Number, .NaN: break
    }
}

enum Kind { Absent = 1, Number }

union Value(Kind)
{
case .Number:
    number: s32
}

func readDefaultTag()->Kind
{
    var value: Value
    return Swag.kindOf(value)     // swc-expected-error {{sema_err_definite_init_use}}
}

func missingTag(value: Value)
{
    switch value     // swc-expected-error {{sema_err_switch_complete_enum_not_exhaustive}}
    {
    case .Number: Swag.require(value.number > 0)
    }
}

enum NonZeroState { Ready = 1, Done }

func missingDefaultReturn(state: NonZeroState)->bool     // swc-expected-error {{sema_err_missing_return}}
{
    switch state     // swc-expected-note {{sema_note_switch_miss_continues}}
    {
    case .Ready: return true
    case .Done:  return false
    }
}
