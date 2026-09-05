#global namespace GenericCallChain

struct Point {}

func(T) relay(value: T)->T
{
    return leaf'T(value)     // swc-expected-note {{sema_note_generic_requested_here}}
}

#test
{
    discard relay(Point{})     // swc-expected-note {{sema_note_generic_requested_here}}
}
