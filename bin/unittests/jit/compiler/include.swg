#global private

const SelfBytes = #include(#file)

func mutateFirst()->u8
{
    var copy = #include(#file)
    copy[0] = 'H'_u8
    return copy[0]
}

func getSecond()->u8
{
    var copy = #include(#file)
    return copy[1]
}

#test
{
    #assert(#typeof(SelfBytes) == [SelfBytes.count] u8)
    #assert(SelfBytes.count > 16)
    #assert(SelfBytes[0] == '#'_u8)
    #assert(SelfBytes[1] == 'g'_u8)
}

#test
{
    const first  = #run mutateFirst()
    const second = #run getSecond()
    #assert(first == 'H'_u8)
    #assert(second == 'g'_u8)
}
