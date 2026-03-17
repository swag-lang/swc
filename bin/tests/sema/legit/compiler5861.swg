#global fileprivate // swc-option sema-only
#global skip
struct A
{
    private a:   s32
}

struct B
{
    private
    {
        a:     s32
        b:     s32
    }
}
