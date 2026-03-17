#global fileprivate

const SelfBytes = #include(#file)

func mutateFirst()->u8
{
    var copy = #include(#file)
    copy[0] = 'H''u8
    return copy[0]
}

func getSecond()->u8
{
    var copy = #include(#file)
    return copy[1]
}

#test
{
    #assert(#typeof(SelfBytes) == [@countof(SelfBytes)] u8)
    #assert(@countof(SelfBytes) > 16)
    #assert(SelfBytes[0] == '#''u8)
    #assert(SelfBytes[1] == 'g''u8)
}

#test
{
    const first = #run mutateFirst()
    const second = #run getSecond()
    #assert(first == 'H''u8)
    #assert(second == 'g''u8)
}
