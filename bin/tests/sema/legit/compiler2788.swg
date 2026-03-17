#global fileprivate // swc-option sema-only
#global skip
func myFunc(val: s32, x: func(s32)->s32)
{
    discard x(val)
}
