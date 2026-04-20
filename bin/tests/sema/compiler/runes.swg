#global fileprivate

const Latin = #runes("hello")
const Mixed = #runes("hé😀")

#assert(#typeof(Latin) == const [..] rune)
#assert(@countof(Latin) == 5)
#assert(Latin[0] == 'h''rune)
#assert(Latin[4] == 'o''rune)

#assert(#typeof(Mixed) == const [..] rune)
#assert(@countof(Mixed) == 3)
#assert(Mixed[0] == 'h''rune)
#assert(Mixed[1] == 'é''rune)
#assert(Mixed[2] == '😀''rune)

#test { const bad = #runes(1) } // swc-expected-error {{sema_err_invalid_type}}
