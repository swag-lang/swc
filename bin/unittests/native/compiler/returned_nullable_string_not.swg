#global private

#[Swag.NoInline]
func maybeText(flag: bool)->string?
{
    if flag do
        return "abc"
    return null
}

#[Swag.NoInline]
func negateReturnedNullable(flag: bool)->bool
{
    if not maybeText(flag) do
        return true
    return false
}

#test
{
    var falseFlag = false
    var trueFlag  = true

    Swag.assert(negateReturnedNullable(falseFlag))
    Swag.assert(not negateReturnedNullable(trueFlag))
}
