#global fileprivate // swc-option sema-only
#global skip
#[Swag.Inline]
func toto()->s32 => 1

//#[Swag.PrintBc]
#test
{
    var r = toto()
}
