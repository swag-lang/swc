#global private
const SelfBytes = #include(#file)

// #include reads own file as byte array
#test
{
    #assert(#typeof(SelfBytes) == [SelfBytes.count] u8)

    Swag.assert(SelfBytes.count > 16)
    Swag.assert(SelfBytes[0] == '#'u8)
    Swag.assert(SelfBytes[1] == 'g'u8)
}

// #include result is mutable when assigned to var
#test
{
    var copy = #include(#file)
    copy[0] = 'H'u8
    Swag.assert(copy[0] == 'H'u8)
    Swag.assert(copy[1] == 'g'u8)
}
