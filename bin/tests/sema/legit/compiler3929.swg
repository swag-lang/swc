#global fileprivate // swc-option sema-only
#global skip
var g: func||(s32)

#test
{
    #[Swag.Mixin]
    func toto()
    {
        g = func(btn) {}
    }

    toto()
}
