#global private
const GlobalValue = 0

enum Color
{
    Red   = 1,
    Green = 2,
    Blue  = 3
}

struct NamedStruct
{
    value: s32
}

#assert(#nameof(GlobalValue) == "GlobalValue")
#assert(#nameof(Color.Red) == "Red")
#assert(#nameof(Color.Green) == "Green")
#assert(#fullnameof(Color.Blue) == "Color.Blue")
#assert(#nameof(NamedStruct) == "NamedStruct")
#assert(#nameof(s32) == "s32")
#assert(#nameof(bool) == "bool")

// #nameof and #fullnameof at runtime
#test
{
    const globalName   = #nameof(GlobalValue)
    const enumName     = #nameof(Color.Green)
    const fullEnumName = #fullnameof(Color.Green)

    Swag.require(globalName == "GlobalValue")
    Swag.require(enumName == "Green")
    Swag.require(fullEnumName == "Color.Green")
}
