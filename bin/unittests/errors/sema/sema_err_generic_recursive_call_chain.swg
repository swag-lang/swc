#global private

struct Point {}

// Both specializations share a declaration, but each needs its own context frame.
// swc-expected-note@+2 {{while checking generic function 'relay' with T = Point}}
// swc-expected-note@+1 {{while checking generic function 'relay' with T = s32}}
func(T) relay(value: T)->s32
{
    #static if T == s32
    {
        return relay'Point(Point{})     // swc-expected-note {{sema_note_generic_requested_here}}
    }
    else
    {
        return value + value     // swc-expected-error {{sema_err_binary_operand_type}}
    }
}

#test
{
    discard relay(1)     // swc-expected-note {{sema_note_generic_requested_here}}
}
