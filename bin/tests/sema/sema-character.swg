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

/*#assert('A' < 'B')
#assert('a' > 'A')
#assert('0' < '9')
#assert('\n' < ' ')*/

#assert('H' == 'H')
#assert('W' == 'W')
#assert('!' == '!')

