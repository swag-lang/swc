#global fileprivate // swc-option sema-only
#global skip
using Swag
#[AttrUsage(AttributeUsage.StructVariable)]
attr T()

struct TOTO
{
    #[T]
    {
        A:     s32
        B:     s32
    }
}
