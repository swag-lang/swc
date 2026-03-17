#global fileprivate // swc-option sema-only
#global skip
struct A {}
impl A
{
    #[Swag.Overload]
    mtd(o: string) opAssign(x: u8) {}
    #[Swag.Overload]
    mtd(o: string) opAssign(x: rune) {}
}

#test
{
    var a: A
    a += 0'u8
}
