#global fileprivate // swc-option sema-only
#global skip
#[Swag.AttrUsage(Swag.AttributeUsage.StructVariable)]
attr toto()

struct A
{
    #[toto]
    x:   s32
}

const C: A{0}
