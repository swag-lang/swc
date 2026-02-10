#global internal

enum OverA { A, B }
enum OverB { A, B }

func overload(x: s32, e: OverA)->s32 { return 10 }
func overload(x: f32, e: OverB)->f32 { return 20.0 }

#test
{
    let r = overload(1.0, .A)
    #assert(#typeof(r) == f32)
}

func fct(x: f32, e: OverB)->f32 { return 20.0 }
#test
{
    let r1 = fct(1.0, .C) // swc-expected-error {{sema_err_auto_scope_missing_enum_value}}
}

struct Vec2
{
    x: f32
    y: f32
}

impl Vec2
{
    func set_axis(axis: OverA, value: f32)
    {
        if axis == .A {
        } elif axis == .B {
        }
    }

    mtd toto()
    {
        if .z > 0.0 {} // swc-expected-error {{sema_err_auto_scope_missing_struct_member}}
    }

    func titi()->Vec2
    {
        set_axis(.A, 1.0)
        return {}
    }
}

#test
{
    let r1 = overload(1.0, .C) // swc-expected-error {{sema_err_no_overload_match}}
}

#test
{
    let r2 = overload(1's32, OverA.A)
    #assert(#typeof(r2) == s32)
}

#test
{
    let r3 = fct(1.0, .A)
    #assert(#typeof(r3) == f32)
}
