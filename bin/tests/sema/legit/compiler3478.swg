#global fileprivate // swc-option sema-only
#global skip
func(T) toto(cb: func||(T, T)) {}

#test
{
    toto(func(x, y: s32) {})
}
