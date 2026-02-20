#global internal

#test
{
    func shiftLeft(a: u32, b: u32)->u32 { return a << b }
    const V = #run shiftLeft(21'u32, 1'u32)
    #assert(#typeof(V) == u32)
    #assert(V == 42'u32)
}

#test
{
    #[Swag.PrintMicro]
    func shiftLeftChain(a: u32, b: u32, c: u32)->u32 { return (a << b) << c }
    const V = #run shiftLeftChain(5'u32, 2'u32, 1'u32)
    #assert(#typeof(V) == u32)
    #assert(V == 40'u32)
}

#test
{
    func shiftLeftStrict(a: u32, b: u32)->u32 { return a << b }
    const V = #run shiftLeftStrict(21'u32, 1'u32, 1'u32) // swc-expected-error {{sema_err_too_many_arguments}}
}
