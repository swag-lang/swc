#global fileprivate // swc-option sema-only
#global skip
#[Swag.EnumFlags]
enum RGB { R, G, B }

func toto(rgb: RGB) {}

#test
{
    toto(.R | .G)
}
