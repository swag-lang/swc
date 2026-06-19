#global fileprivate

#[Swag.NoInline]
func maybeText(flag: bool)->#null string
{
    if flag do
        return "abc"
    return null
}

#[Swag.NoInline]
func negateReturnedNullable(flag: bool)->bool
{
    if !maybeText(flag) do
        return true
    return false
}

#test
{
    var falseFlag = false
    var trueFlag  = true

    @assert(negateReturnedNullable(falseFlag))
    @assert(!negateReturnedNullable(trueFlag))
}
