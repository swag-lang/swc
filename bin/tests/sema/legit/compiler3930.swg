#global fileprivate // swc-option sema-only
#global skip
#test
{
    var g: s32

    #[Swag.Macro]
    func toto()
    {
        #up g = 0
    }

    toto()
}
