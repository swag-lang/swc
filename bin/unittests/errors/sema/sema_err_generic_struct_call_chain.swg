#global private

struct(T) Box
{
    value: T
}

impl Box
{
    mtd read()->T
    {
        return .value + .value     // swc-expected-error {{sema_err_binary_operand_type}}
    }
}

struct Point {}

func(T) readBox(value: T)->T
{
    let box: Box'T = {value}     // swc-expected-note {{sema_note_generic_requested_here}}
    return box.read()
}

#test
{
    discard readBox(Point{})     // swc-expected-note {{sema_note_generic_requested_here}}
}
