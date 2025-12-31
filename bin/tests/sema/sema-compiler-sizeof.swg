#global internal

#assert(#sizeof(u8) == 1)
#assert(#sizeof(u16) == 2)
#assert(#sizeof(u32) == 4)
#assert(#sizeof(u64) == 8)
#assert(#sizeof(s8) == 1)
#assert(#sizeof(s16) == 2)
#assert(#sizeof(s32) == 4)
#assert(#sizeof(s64) == 8)
#assert(#sizeof(f32) == 4)
#assert(#sizeof(f64) == 8)
#assert(#sizeof(bool) == 1)
#assert(#sizeof(rune) == 4)
#assert(#sizeof(any) == 16)

#assert(#sizeof('r') == 4)
#assert(#sizeof("r") == 16)
