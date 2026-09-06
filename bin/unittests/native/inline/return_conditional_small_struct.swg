#global private

struct SmallColor
{
    raw: u32
}

#[Swag.Inline, Swag.ConstExpr]
func makeColor(raw: u32)->SmallColor
{
    return {raw}
}

#[Swag.Inline]
func chooseColor(condition: bool)->SmallColor
{
    return condition ? makeColor(0xFFFFFFFF) : makeColor(0xFF000000)
}

#[Swag.NoInline]
func checkColor(condition: bool, expected: u32)
{
    let color = chooseColor(condition)
    Swag.assert(color.raw == expected)
}

#test
{
    checkColor(true, 0xFFFFFFFF)
    checkColor(false, 0xFF000000)
}
