#global fileprivate // swc-option sema-only
#global skip
using Swag

#[AttrUsage(AttributeUsage.All)]
attr NC()

#[NC]
func toto() {}

#[NC]
struct Point {}

#[NC]
enum Color
{
    Z
}
