#global fileprivate // swc-option sema-only
#global skip
#test
{
    func B(a: s32) {}

    func A()
    {
        B(0)
        var a = 0
    }
}
