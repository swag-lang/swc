#global fileprivate // 


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
    @assert(cast(s32) a == 12)
}

#test
{
    func takes(v: s32) {}
    var a: any = 12
    var b: s32 = cast() a
    takes(b)
    @assert(b == 12)
}


#test
{
    var a: any = true
    var passed = false
    if cast(bool) a
    {
        passed = true
    }
    @assert(passed)
}
