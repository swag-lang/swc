#global fileprivate // swc-option sema-only
#global skip
struct A {}

impl A
{
    func opEquals(me, v: u32) => true
}
