#global fileprivate // swc-option sema-only
#global skip
func(T) sort(value: T, cb: func(T, T)->s32) {}

#test
{
    sort(0's32, func(x, y) => x - y)
}
