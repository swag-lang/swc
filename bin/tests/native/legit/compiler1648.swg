// swc-option suite-test

#global fileprivate
#global skip
//#[Swag.PrintBc]
#test
{
    var x = 0xFFFFFFFF'u64
    x %= 16'u32

    let m: u32 = 16
    x %= cast(u64) m
}
