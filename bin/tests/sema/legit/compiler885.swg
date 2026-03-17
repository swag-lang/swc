#global fileprivate // swc-option sema-only
#global skip
//#[Swag.PrintBc]
#test
{
    var currentValue = 3
    while currentValue
    {
        currentValue -= 1
    }

    @assert(currentValue == 0)
}
