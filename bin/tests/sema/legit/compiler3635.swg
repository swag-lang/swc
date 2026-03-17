#global fileprivate // swc-option sema-only
#global skip
struct(T) ArrayPtr
{
    ptr: *T
}

struct XXX
{
    x:   ArrayPtr'XXX
}

#assert(#sizeof(XXX) == #sizeof(*void))
