#global fileprivate // swc-option sema-only
#global skip
#[Swag.Macro]
func assert(expr: #code bool)
{
    if !#inject(expr) do
        @assert(false)
}

#test
{
    assert(true)
}
