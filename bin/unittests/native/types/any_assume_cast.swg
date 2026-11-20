#global private

#[Swag.NoInline]
func extractAssumedAny(value: any)->s64 => assume cast(s64, value)

#[Swag.NoInline]
func receiveAssumedAny(value: s64)->s64 => value

#test
{
    const boxed: any = 987654321's64
    let value: s64 = assume cast(s64, boxed)
    Swag.require(value == 987654321)
}

#test
{
    const boxed: any = true
    let value: bool = assume cast(bool, boxed)
    Swag.require(value)
}

#test
{
    var value: s64 = 73
    Swag.require(extractAssumedAny(value) == 73)
    var boxed:     any = value
    let extracted: s64 = assume cast(s64, boxed)
    Swag.require(extracted == 73)
    Swag.require(receiveAssumedAny(assume cast(s64, boxed)) == 73)
}
