#global private

struct Vec { x: s32 }

var g_target: Vec

func consume(v: Vec) {}

// '#fwd' as an assignment modifier requires an enclosing '#fwd' function.
func noFwdAssign(v: Vec)
{
    g_target = #fwd v // swc-expected-error {{parser_err_fwd_outside}}
}

// '#fwd' as a call-argument prefix requires an enclosing '#fwd' function.
func noFwdArg(v: Vec)
{
    consume(#fwd v) // swc-expected-error {{parser_err_fwd_outside}}
}
