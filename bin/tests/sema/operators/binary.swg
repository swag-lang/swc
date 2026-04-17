#global fileprivate

#test
{
    var a, b: s32
    a = b / 0 // swc-expected-error {{safety_err_division_zero}}
}

#test
{
    var a, b: s32
    a = b % 0 // swc-expected-error {{safety_err_division_zero}}
}

#test
{
    var a, b: s32
    a = b / (1 - 1) // swc-expected-error {{safety_err_division_zero}}
}

#test
{
    var a, b: s32
    a = b % (2 - 2) // swc-expected-error {{safety_err_division_zero}}
}

#test
{
    var a: s32
    var b: bool = true
    a = a + b // swc-expected-error {{sema_err_binary_operand_type}}
}

#test
{
    let r = 'A''rune
    let anded = r & 0x7F
    let shifted = r << 1

    #assert(#typeof(anded) == rune)
    #assert(#typeof(shifted) == rune)
    #assert(('A''rune & 0x7F) == 'A''rune)
    #assert(('A''rune << 1) == cast(rune) 130'u32)
}
