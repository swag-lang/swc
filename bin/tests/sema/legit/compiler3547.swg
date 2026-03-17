#global fileprivate // swc-option sema-only
#global skip
#[Swag.Incomplete]
enum RGB: s32 { R, G, B }

func toto(rgb: RGB) {}

#test
{
    toto(0)
}
