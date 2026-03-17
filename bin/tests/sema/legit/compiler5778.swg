#global fileprivate // swc-option sema-only
#global skip
alias HookEvent = func||()->bool

#[Swag.Optimize(.All, false)]
//#[Swag.PrintGenBc]
func toto(x: HookEvent = null)
{
    var y: HookEvent = x
}
