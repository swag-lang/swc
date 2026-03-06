#global fileprivate
#global skip
#[Swag.AttrUsage(Swag.AttributeUsage.StructVariable)]
attr toto()

struct A
{
    #[toto]
    x:   s32
}

const C: A{0}
