#global fileprivate // swc-option sema-only
#global skip
#test
{
    var x: f32
    var b: bool
    x = b ? 1 : 1.0
}
