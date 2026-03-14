#global fileprivate // swc-option suite-test


#test
{
    var a: any = 12
    var b: s32 = cast() a
    @assert(b == 12)
}

#test
{
    func takes(v: s32) {}
    var a: any = 12
}

#test
{
    func takes(v: s32) {}
    var a: any = 12
    takes(cast() a)
}


#test
{
    var a: any = true
    if cast(bool) a {}
}
