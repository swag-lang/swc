#global private

func semaTest001()
{
    let r       = 'A'_rune
    let anded   = r & 0x7F
    let shifted = r << 1

    #assert(#typeof(anded) == rune)
    #assert(#typeof(shifted) == rune)
    #assert(('A'_rune & 0x7F) == 'A'_rune)
    #assert(('A'_rune << 1) == cast(rune, 130_u32))
}
