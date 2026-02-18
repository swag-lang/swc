#global internal

#test
{
    #[Swag.PrintMicro]
    func add(a: s32, b: s32)->s32 { return a + b }
    const V = #run add(39, 3)
    #assert(#typeof(V) == s32)
    #assert(V == 42)
}

#test
{
    func add(a: f64, b: f64)->f64 { return a + b }
    const V = #run add(1.5'f64, 2.25'f64)
    #assert(#typeof(V) == f64)
    #assert(V == 3.75'f64)
}
