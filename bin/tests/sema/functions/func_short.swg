#global internal

func A() => true
func B(a: s32, b: s32) => a + b
func C(a: s32) => cast(f32) a
func D(a: s32) => a
func E(a: s32) => a > 0
func F(a, b: s32) => a - b
#test
{
    #assert(#typeof(A()) == bool)
    #assert(#typeof(B(2, 3)) == s32)
    #assert(#typeof(C(12)) == f32)
    #assert(#typeof(D(7)) == s32)
    #assert(#typeof(E(7)) == bool)
    #assert(#typeof(F(9, 3)) == s32)
    @assert(D(7) == 7)
    @assert(E(0) == false)
    @assert(E(1) == true)
    @assert(F(9, 3) == 6)
}

#test
{
    D(1.5) // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    F(1, 2, 3) // swc-expected-error {{sema_err_too_many_arguments}}
}
