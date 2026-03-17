#global fileprivate // swc-option sema-only
#global skip
func toto(x: u8) {}

#test
{
    toto(0xFF)
}
