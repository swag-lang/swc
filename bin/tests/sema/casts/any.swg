#global fileprivate // swc-option sema-only

#test
{
    var a: any = 12
    var b: s32 = a // swc-expected-error {{sema_err_cannot_cast}}
}

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
    takes(a) // swc-expected-error {{sema_err_cannot_cast}}
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
    if a {} // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var a: any = true
    if cast(bool) a {}
}
