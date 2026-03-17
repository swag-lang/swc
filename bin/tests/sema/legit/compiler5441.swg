#global fileprivate // swc-option sema-only
#global skip
func toto(x: &s32) {}

#test
{
    var a = 0
    a.toto()
}
