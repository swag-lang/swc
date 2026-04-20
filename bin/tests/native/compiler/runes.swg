#global fileprivate

const Token = #runes("A😀B")

func runeCount(text: const [..] rune)->u64
{
    return @countof(text)
}

func secondRune(text: const [..] rune)->rune
{
    return text[1]
}

#test
{
    #assert(#typeof(Token) == const [..] rune)
    @assert(@countof(Token) == 3)
    @assert(Token[0] == 'A''rune)
    @assert(Token[1] == '😀''rune)
    @assert(Token[2] == 'B''rune)

    @assert(runeCount(#runes("hé")) == 2)
    @assert(secondRune(#runes("hé")) == 'é''rune)
}
