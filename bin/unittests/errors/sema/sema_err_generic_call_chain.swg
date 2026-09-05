#global private

struct Point {}

func(T) doubleIt(value: T)->T
{
    return value + value     // swc-expected-error {{sema_err_binary_operand_type}}
}

func(T) relay(value: T)->T
{
    return doubleIt(value)     // swc-expected-note {{sema_note_generic_requested_here}}
}

#test
{
    discard relay(Point{})     // swc-expected-note {{sema_note_generic_requested_here}}
}
