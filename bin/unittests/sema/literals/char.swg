#global private

#assert('\n'_u8 == 10)
#assert('\n'_u16 == 10)
#assert('\n'_u32 == 10)
#assert('\n'_u64 == 10)
#assert('\n' == 10)
#assert('\n' == 10_u8)
#assert('\n' == 10_u16)
#assert('\n' == 10_u32)
#assert('\n' == 10_u64)
#assert('\n'_rune == '\n')
#assert('a'_rune == 'a')
#assert('\0'_rune == '\0')
#assert(65_rune == 'A')
#assert(0xFFFD_rune == '\uFFFD')
#assert(#typeof(65_rune) == rune)

#assert('A'_u8 == 65)
#assert('Z'_u8 == 90)
#assert('a'_u8 == 97)
#assert('z'_u8 == 122)
#assert('0'_u8 == 48)
#assert('9'_u8 == 57)

#assert(' '_u8 == 32)
#assert('@'_u8 == 64)
#assert('~'_u8 == 126)

#assert('\t'_u8 == 9)
#assert('\r'_u8 == 13)
#assert('\0'_u8 == 0)
#assert('\''_u8 == 39)
#assert('\\'_u8 == 92)
#assert('\n'_u8 == 10)

#assert('\x41'_u8 == 65)
#assert('\x7F'_u8 == 127)
#assert('\xFF'_u8 == 255)
#assert('\x00'_u8 == 0)

#assert('é'_u32 == 0xE9)
#assert('é'_u16 == 0xE9)
#assert('é'_u64 == 0xE9)
#assert('☃'_u32 == 0x2603)
#assert('☃'_u64 == 0x2603)
#assert('😀'_u32 == 0x1F600)
#assert('😀'_u64 == 0x1F600)

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

#assert('\u0061'_u32 == 0x61)
#assert('\u00E9'_u32 == 0xE9)
#assert('\u4E00'_u32 == 0x4E00)
#assert('\u0000'_u32 == 0)

// The closing quote separates the literal from its suffix, so the suffix follows it
// immediately.
#assert('A'_u8 == 65)
#assert(' '_u32 == 32)

// Trivia may separate a numeric literal from its explicit suffix marker.
#assert(1_s32 == 1)
#assert(1_s32 == 1)
#assert(1 /* comment */ _s32 == 1)
#assert(#typeof(1_s32) == s32)
