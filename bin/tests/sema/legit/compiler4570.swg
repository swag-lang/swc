#global fileprivate // swc-option sema-only
#global skip
#test
{
    var x = [1'u8, 1'u8]
    var y = cast([..] u16) x
}
