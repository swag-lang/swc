#global fileprivate // swc-option sema-only
#global skip
#global skip

#[Swag.Mixin]
func toto(stmt: #code void)
{
    for 5
    {
        #inject(stmt) => { break = break; }
    }
}
