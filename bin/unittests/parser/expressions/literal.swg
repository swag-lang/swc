#global private

#assert(cast(s32, #sizeof(MyStruct1)) == 9)
#assert(#typeof(0_s8 + 1_s8) == s8)
#assert('A'_u8 == 65)
#assert(#typeof('😀'_rune) == rune)
