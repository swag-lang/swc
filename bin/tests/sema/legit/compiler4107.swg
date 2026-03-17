#global fileprivate // swc-option sema-only
#global skip
struct T {}

impl T
{
    mtd opDrop()
    {
        @assert(me == &G)
    }
}

var G: T
