#global fileprivate // swc-option sema-only
#global skip
alias T = func()->void

//#[Swag.PrintBc]
#test
{
    var x: T
    if !x
    {
    }

    if x
    {
        @assert(false)
    }
}
