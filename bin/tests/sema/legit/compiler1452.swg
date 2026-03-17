#global fileprivate // swc-option sema-only
#global skip
struct S {}

impl S
{
    #[Swag.Macro]
    func visitBytes(me, stmt: #code void)
    {
        #macro
        {
            #inject(stmt)
        }
    }
}
