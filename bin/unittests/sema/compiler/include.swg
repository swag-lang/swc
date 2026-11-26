#global private

const SelfBytes = #include(#file)

#assert(#typeof(SelfBytes) == [SelfBytes.count] u8)

#assert(SelfBytes.count > 16)
#assert(SelfBytes[0] == '#'_u8)
#assert(SelfBytes[1] == 'g'_u8)
