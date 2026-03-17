#global fileprivate // swc-option sema-only
#global skip
func toto()->f32 => 0
#test
{
    var x: s32
    x = cast() toto()
}
