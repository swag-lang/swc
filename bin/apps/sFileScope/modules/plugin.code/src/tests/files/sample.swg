#global public

using Core

// Swag lexer verification fixture.
func answer(value: u32)->u32
{
    let doubled = value * 2
    if doubled > 40 do
        return doubled + 2
    return 0
}

