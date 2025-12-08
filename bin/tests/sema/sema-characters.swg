#assert('\n''u8 == 10)
#assert('\n''u16 == 10)
#assert('\n''u32 == 10)
#assert('\n''u64 == 10)
#assert('\n' == 10)
#assert('\n' == 10'u8)
#assert('\n' == 10'u16)
#assert('\n' == 10'u32)
#assert('\n' == 10'u64)
#assert('a''rune == 'a')

#assert('A''u8 == 65)
#assert('Z''u8 == 90)
#assert('a''u8 == 97)
#assert('z''u8 == 122)
#assert('0''u8 == 48)
#assert('9''u8 == 57)

#assert(' ''u8 == 32)
#assert('@''u8 == 64)

#assert('\t''u8 == 9)
#assert('\r''u8 == 13)
#assert('\0''u8 == 0)
#assert('\'''u8 == 39)

#assert('\x41''u8 == 65)
#assert('\x7F''u8 == 127)
#assert('\xFF''u8 == 255)

#assert('é''u32 == 0xE9)
#assert('☃''u32 == 0x2603)
#assert('😀''u32 == 0x1F600)

#assert('A' < 'B')
#assert('a' > 'A')
#assert('0' < '9')
#assert('\n' < ' ')

#assert('H' == 'H')
#assert('W' == 'W')
#assert('!' == '!')

#assert('\u0000' == '\0')
#assert('\u0061' == 'a')
#assert('\u00E9' == 'é')
#assert('\u4E00' == '一')

#assert('a''s8 == 0)     // swc-expected-error {{sema_err_cannot_cast}}
#assert('a''s16 == 0)    // swc-expected-error {{sema_err_cannot_cast}}
#assert('a''s32 == 0)    // swc-expected-error {{sema_err_cannot_cast}}
#assert('a''s64 == 0)    // swc-expected-error {{sema_err_cannot_cast}}

