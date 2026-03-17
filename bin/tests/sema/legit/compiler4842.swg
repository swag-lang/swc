#global fileprivate // swc-option sema-only
#global skip
struct A {}
impl A
{
    mtd opAffect(x: bool) {}
}

#test
{
    let a: A = true
}
