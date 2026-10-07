#global private

#[Swag.NoInline]
func extractContextualAny(value: any)->s64 => assume cast(value)

#[Swag.NoInline]
func receiveContextualAny(value: s64)->s64 => value

#test
{
    const boxed: any = 987654321's64
    let value: s64 = assume cast(boxed)
    Swag.assert(value == 987654321)
}

#test
{
    const boxed: any = true
    let value: bool = assume cast(boxed)
    Swag.assert(value)
}

#test
{
    var value: s64 = 73
    Swag.assert(extractContextualAny(value) == 73)
    var boxed:     any = value
    let extracted: s64 = assume cast(boxed)
    Swag.assert(extracted == 73)
    Swag.assert(receiveContextualAny(assume cast(boxed)) == 73)
}
