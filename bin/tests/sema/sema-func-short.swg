#global internal

func A() => true
func B(a: s32, b: s32) => a + b
func C(a: s32) => cast(f32) a
#test
{
    #assert(#typeof(A()) == bool)
    #assert(#typeof(B(2, 3)) == s32)
    #assert(#typeof(C(12)) == f32)
}