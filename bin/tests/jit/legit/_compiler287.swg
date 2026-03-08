#global fileprivate

//#[Swag.PrintBc]
#run
{
    var a: bool = true
    let b  = &a
    let c  = dref b
    @assert(c == true)
}

#run
{
    var a: s32 = 666
    let b  = &a
    let c  = dref b
    @assert(c == 666)
}
