#global fileprivate // swc-option sema-only
#global skip
#[Swag.Overload]
func toto(x: u8) {}
#[Swag.Overload]
func toto(x: u16) {}
#[Swag.Overload]
func toto(x: u32) {}

#test
{
    toto(0xFFFFFFFF)
}
