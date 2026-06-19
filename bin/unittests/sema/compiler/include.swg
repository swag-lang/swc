#global fileprivate

const SelfBytes = #include(#file)

#assert(#typeof(SelfBytes) == [@countof(SelfBytes)] u8)

#assert(@countof(SelfBytes) > 16)
#assert(SelfBytes[0] == '#''u8)
#assert(SelfBytes[1] == 'g''u8)
