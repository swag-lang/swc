#global fileprivate // swc-option sema-only
#global skip
//#global skip
#test
{
    struct V { x: s32 }
    func toto(v: V) {}
    toto({4})
}
