#global fileprivate // 
const SelfBytes = #include(#file)

// #include reads own file as byte array
#test
{
    #assert(#typeof(SelfBytes) == [@countof(SelfBytes)] u8)

    @assert(@countof(SelfBytes) > 16)
    @assert(SelfBytes[0] == '#''u8)
    @assert(SelfBytes[1] == 'g''u8)
}

// #include result is mutable when assigned to var
#test
{
    var copy = #include(#file)
    copy[0] = 'H''u8
    @assert(copy[0] == 'H''u8)
    @assert(copy[1] == 'g''u8)
}
