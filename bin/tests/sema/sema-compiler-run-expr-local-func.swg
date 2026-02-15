#global internal

#test
{
    func localConst()->s32 { return 42 }
    const V = #run localConst()
    #assert(V == 42)
}

#test
{
    func depA()->s32 { return 7 }
    func depB()->s32 { return depA() }
    const V = #run depB()
    #assert(V == 7)
}

#test
{
    func takesArg(v: s32)->s32 { return 1 }
    const V = #run takesArg() // swc-expected-error {{sema_err_too_few_arguments}}
}

#test
{
    func takesArg(v: s32)->s32 { return 1 }
    const V = #run takesArg("bad") // swc-expected-error {{sema_err_cannot_cast}}
}
/*
#[Swag.PrintMicro()]
#test
{
    func takesArg(v: s32)->s32 { return v }
    #assert(#run takesArg(1) == 1)
}
*/