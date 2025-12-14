#assert('\n''u8 == 10)
#assert('\n''u16 == 10)
#assert('\n''u32 == 10)
#assert('\n''u64 == 10)
#assert('\n' == 10)
#assert('\n' == 10'u8)
#assert('\n' == 10'u16)
#assert('\n' == 10'u32)
#assert('\n' == 10'u64)
#assert('\n''rune == '\n')
#assert('a''rune == 'a')
#assert('\0''rune == '\0')

#assert('A''u8 == 65)
#assert('Z''u8 == 90)
#assert('a''u8 == 97)
#assert('z''u8 == 122)
#assert('0''u8 == 48)
#assert('9''u8 == 57)

#assert(' ''u8 == 32)
#assert('@''u8 == 64)
#assert('~''u8 == 126)

#assert('\t''u8 == 9)
#assert('\r''u8 == 13)
#assert('\0''u8 == 0)
#assert('\'''u8 == 39)
#assert('\\''u8 == 92)
#assert('\n''u8 == 10)

#assert('\x41''u8 == 65)
#assert('\x7F''u8 == 127)
#assert('\xFF''u8 == 255)
#assert('\x00''u8 == 0)

#assert('é''u32 == 0xE9)
#assert('é''u16 == 0xE9)
#assert('é''u64 == 0xE9)
#assert('☃''u32 == 0x2603)
#assert('☃''u64 == 0x2603)
#assert('😀''u32 == 0x1F600)
#assert('😀''u64 == 0x1F600)

#assert('A' < 'B')
#assert('a' > 'A')
#assert('0' < '9')
#assert('\n' < ' ')
#assert('A' <= 'A')
#assert('B' >= 'A')
#assert(('A' <=> 'B') == -1)
#assert(('B' <=> 'A') == 1)
#assert(('A' <=> 'A') == 0)

#assert('H' == 'H')
#assert('W' == 'W')
#assert('!' == '!')
#assert('H' != 'W')

#assert('\u0000' == '\0')
#assert('\u0061' == 'a')
#assert('\u00E9' == 'é')
#assert('\u4E00' == '一')

#assert('\u0061''u32 == 0x61)
#assert('\u00E9''u32 == 0xE9)
#assert('\u4E00''u32 == 0x4E00)
#assert('\u0000''u32 == 0)

#assert('😀''u8 == 0)   // swc-expected-error {{sema_err_literal_overflow}}

#assert('a''s8 == 97)   // swc-expected-error {{sema_err_cannot_cast}}
#assert('a''s16 == 97)  // swc-expected-error {{sema_err_cannot_cast}}
#assert('a''s32 == 97)  // swc-expected-error {{sema_err_cannot_cast}}
#assert('a''s64 == 97)  // swc-expected-error {{sema_err_cannot_cast}}


