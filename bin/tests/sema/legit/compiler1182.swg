#global fileprivate // swc-option sema-only
#global skip
#[Swag.AttrUsage(Swag.AttributeUsage.StructVariable)]
attr T()

struct TOTO
{
    #[T]
    {
        A:     s32
        B:     s32
    }
}
