#global namespace GlobalIfPlatform

public const Enabled = true

public struct Value { data: s32 = 42 }

#test
{
    var value: Value
    Swag.require(answer() == 42)
    Swag.require(genericAnswer(9) == 42)
    Swag.require(value.read() == 42)
    Swag.require(first == 11 and second == 22)
    let selected: Choice = Choice{value: 31}
    let result:   Result = selected.value
    Swag.require(result == 31)
    Swag.require(Shared.selected() == 19)
}
