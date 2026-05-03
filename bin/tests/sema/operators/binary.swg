#global fileprivate

func semaTest001()
{
    let r = 'A''rune
    let anded = r & 0x7F
    let shifted = r << 1

    #assert(#typeof(anded) == rune)
    #assert(#typeof(shifted) == rune)
    #assert(('A''rune & 0x7F) == 'A''rune)
    #assert(('A''rune << 1) == cast(rune) 130'u32)
}
