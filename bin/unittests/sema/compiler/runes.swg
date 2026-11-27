#global private

const Latin = #runes("hello")
const Mixed = #runes("hé😀")

#assert(#typeof(Latin) == const [..] rune)
#assert(Latin.count == 5)
#assert(Latin[0] == 'h'_rune)
#assert(Latin[4] == 'o'_rune)

#assert(#typeof(Mixed) == const [..] rune)
#assert(Mixed.count == 3)
#assert(Mixed[0] == 'h'_rune)
#assert(Mixed[1] == 'é'_rune)
#assert(Mixed[2] == '😀'_rune)
