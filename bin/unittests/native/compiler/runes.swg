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
    Swag.require(Token.count == 3)
    Swag.require(Token[0] == 'A'rune)
    Swag.require(Token[1] == '😀'rune)
    Swag.require(Token[2] == 'B'rune)

    Swag.require(runeCount(#runes("hé")) == 2)
    Swag.require(secondRune(#runes("hé")) == 'é'rune)
}
