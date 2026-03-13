#global fileprivate // swc-option suite-test

#test
{
    var raw: u64 = 0x1234
    var ptr = cast(*void) raw
    var roundtrip = cast(u64) ptr

    @assert(roundtrip == raw)
    @assert(ptr == cast(*void) roundtrip)
}

#test
{
    var raw: u64 = 0xABCD
    var ptr = cast([*]u8) raw
    var roundtrip = cast(u64) ptr

    @assert(roundtrip == raw)
    @assert(ptr == cast([*]u8) roundtrip)
}
