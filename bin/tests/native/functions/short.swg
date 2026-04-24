#global fileprivate // 

func A() => true
func B(a: s32, b: s32) => a + b
func C(a: s32) => cast(f32) a
func D(a: s32) => a
func E(a: s32) => a > 0
func F(a, b: s32) => a - b
#[Swag.NoInline]
func G(x: f32) => x < 0 ? -1 : 1
#[Swag.NoInline]
func H(x: f64) => x < 0 ? -1.5 : 1.5
#[Swag.NoInline]
func I(current, target, speed: f32)->f32
{
    let distance = target - current
    return current + G(distance) * speed
}
#test
{
    #assert(#typeof(A()) == bool)
    #assert(#typeof(B(2, 3)) == s32)
    #assert(#typeof(C(12)) == f32)
    #assert(#typeof(D(7)) == s32)
    #assert(#typeof(E(7)) == bool)
    #assert(#typeof(F(9, 3)) == s32)
    #assert(#typeof(G(1'f32)) == s32)
    #assert(#typeof(H(1'f64)) == f64)
    #assert(#typeof(I(1'f32, 3'f32, 0.25'f32)) == f32)
    @assert(D(7) == 7)
    @assert(E(0) == false)
    @assert(E(1) == true)
    @assert(F(9, 3) == 6)
    @assert(G(-2'f32) == -1)
    @assert(G(2'f32) == 1)
    @assert(H(-2'f64) == -1.5)
    @assert(H(2'f64) == 1.5)
    @assert(I(1'f32, 3'f32, 0.25'f32) == 1.25'f32)
}
