#global fileprivate // swc-option sema-only
#global skip
#global skip
func toto(x: f32, y: bool) {}
func toto(x: bool, y: bool) {}

#test
{
    toto(1.0)
}
