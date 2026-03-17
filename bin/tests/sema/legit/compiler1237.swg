#global fileprivate
#global skip
alias T = func()->void

//#[Swag.PrintBc]
#test
{
    var x: *s32
    if !x
    {
    }

    if x
    {
        @assert(false)
    }
}
