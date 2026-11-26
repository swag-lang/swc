#global private

#[Swag.NoInline]
func maybeText(flag: bool)->string?
{
    if flag
    {
        return "abc"
    }
    return null
}

#[Swag.NoInline]
func negateReturnedNullable(flag: bool)->bool
{
    if not maybeText(flag)
    {
        return true
    }
    return false
}

#test
{
    var falseFlag = false
    var trueFlag  = true

    Swag.require(negateReturnedNullable(falseFlag))
    Swag.require(not negateReturnedNullable(trueFlag))
}
