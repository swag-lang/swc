#global fileprivate // swc-option sema-only
#global skip
#[Swag.Mixin]
func mac(stmt: #code void)
{
    #inject(stmt)
}

#test
{
    mac()
    {
        return
    }
}
