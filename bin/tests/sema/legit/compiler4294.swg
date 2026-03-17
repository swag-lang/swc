#global fileprivate // swc-option sema-only
#global skip
func toto(x: rune) {}

#test
{
    toto(0xFFFFFFFF)
}
