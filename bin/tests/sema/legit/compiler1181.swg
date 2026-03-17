#global fileprivate // swc-option sema-only
#global skip
using Swag
#[AttrUsage(AttributeUsage.EnumValue)]
attr T()

enum TITI
{
    #[T]
    A
}
