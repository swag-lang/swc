#global namespace GlobalIfPlatform

public const Enabled = true

public struct Value { data: s32 = 42 }

#test
{
    var value: Value
    Swag.assert(answer() == 42)
    Swag.assert(genericAnswer(9) == 42)
    Swag.assert(value.read() == 42)
    Swag.assert(first == 11 and second == 22)
    let selected: Choice = Choice{value: 31}
    let result:   Result = selected.value
    Swag.assert(result == 31)
    Swag.assert(Shared.selected() == 19)
}
