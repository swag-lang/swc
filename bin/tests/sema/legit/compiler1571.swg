#global fileprivate // swc-option sema-only
#global skip
struct Point
{
    x:   s64 = 1
}

#test
{
    var x:   Point
    var ptr: const *void = cast(const *void) x
}
