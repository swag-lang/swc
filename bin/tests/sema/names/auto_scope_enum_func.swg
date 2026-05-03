#global fileprivate

enum OverA { A, B }
enum OverB { A, B }

#[Swag.EnumFlags]
enum OverFlags: u8
{
    A
    B
}

func overload(x: s32, e: OverA)->s32 { return 10 }
func overload(x: f32, e: OverB)->f32 { return 20.0 }
func withFlags(e: OverFlags)->OverFlags { return e }

func semaTest001()
{
    let r = overload(1.0, .A)
    #assert(#typeof(r) == f32)
}

func fct(x: f32, e: OverB)->f32 { return 20.0 }

struct Vec2
{
    x: f32
    y: f32
}

func semaTest002()
{
    let r2 = overload(1's32, OverA.A)
    #assert(#typeof(r2) == s32)
}

func semaTest003()
{
    let r3 = fct(1.0, .A)
    #assert(#typeof(r3) == f32)
}

func semaTest004()
{
    let flags = withFlags(.A | .B)
    @assert(flags == OverFlags.A | OverFlags.B)
}
