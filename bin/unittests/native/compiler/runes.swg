#global private

const Token = #runes("A😀B")

func runeCount(text: const [..] rune)->u64
{
    return text.count
}

func secondRune(text: const [..] rune)->rune
{
    return text[1]
}

#test
{
    #assert(#typeof(Token) == const [..] rune)
    Swag.assert(Token.count == 3)
    Swag.assert(Token[0] == 'A'rune)
    Swag.assert(Token[1] == '😀'rune)
    Swag.assert(Token[2] == 'B'rune)

    Swag.assert(runeCount(#runes("hé")) == 2)
    Swag.assert(secondRune(#runes("hé")) == 'é'rune)
}
