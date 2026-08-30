#global private

const SelfBytes = #include(#file)

#assert(#typeof(SelfBytes) == [SelfBytes.count] u8)

#assert(SelfBytes.count > 16)
#assert(SelfBytes[0] == '#'u8)
#assert(SelfBytes[1] == 'g'u8)
