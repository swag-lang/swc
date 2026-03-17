#global fileprivate // swc-option sema-only
#global skip
#test
{
    var x   = 0
    let ptr = cast([*] u8) &x

    dref (ptr + 1) = 1
    @assert(x == 256)
}
