#global fileprivate // swc-option sema-only
#global skip
interface I
{
    mtd toto();
}

struct A {}

impl I for A
{
    #[Swag.Warning("Wrn0006", Swag.WarningLevel.Enable)]
    mtd impl toto() {}
}
