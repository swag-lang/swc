#global fileprivate // swc-option sema-only
#global skip
#test
{
    var x: [2] const *void
    var y: u64
    x[0] = cast(const *void) y
}
