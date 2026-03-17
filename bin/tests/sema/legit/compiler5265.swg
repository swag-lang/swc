#global fileprivate // swc-option sema-only
#global skip
func toto(x: s32) {}

#test
{
    toto(0's8)
}
