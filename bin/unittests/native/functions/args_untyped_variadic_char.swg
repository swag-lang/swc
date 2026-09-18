#global private

// An untyped character literal passed to an untyped variadic parameter arrives as a rune, as it
// does when it is cast to 'any': the compile-time 'character' type never reaches run time.

func firstRune(values: ...)->rune
{
    Swag.assert(Swag.kindOf(values[0]) == rune)
    return cast #assume (rune) values[0]
}

func kindName(values: ...)->string? => Swag.kindOf(values[0]).name

#test
{
    Swag.assert(firstRune('A') == 'A')
    Swag.assert(firstRune('é') == 'é')
    Swag.assert(kindName('z') == "rune")

    let fromLiteral: any = 'x'
    Swag.assert(Swag.kindOf(fromLiteral) == rune)
}
