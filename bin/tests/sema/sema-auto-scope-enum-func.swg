#global internal

enum OverA { A, B }
enum OverB { A, B }

func overload(x: s32, e: OverA)->s32 { return 10 }
func overload(x: f32, e: OverB)->f32 { return 20.0 }

#test
{
    // `.A` must be resolved using the selected overload's parameter enum type.
    // The first argument drives overload choice.
    let r = overload(1.0, .A)
    #assert(#typeof(r) == f32)
    //let r1 = overload(1.0, .C)
}

func fct(x: f32, e: OverB)->f32 { return 20.0 }
#test
{
    let r1 = fct(1.0, .C) // swc-expected-error {{sema_err_auto_scope_missing_value}}
}