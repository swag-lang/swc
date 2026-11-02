#global private

#[Swag.Inline]
func fill(buffer: *u8, size: u32)->bool
{
    let bytes = cast([*] u8, buffer)
    var done  = 0'u32
    while done < size
    {
        let count = Swag.min(size - done, 256'u32)
        for i in count do bytes[done + i] = 42
        done += count
    }
    return true
}
func fillChunks(buffer: [..] u8) fail
{
    var done = 0'u64
    while done < buffer.count
    {
        let chunk = cast(u32, buffer.count - done)
        if not fill(buffer.buffer + done, chunk) do fail Swag.SystemError{"fill failed"}
        done += chunk
    }
}
#test
{
    // The argument's lowered .buffer must still name the caller's slice while
    // its detached initializer is analyzed in fill's inline scope.
    var data: [1026] u8
    data[0]    = 17
    data[1025] = 29
    expect fillChunks(data[1 until 1025])
    Swag.assert(data[0] == 17 and data[1025] == 29)
    for value in data[1 until 1025] do
        Swag.assert(value == 42)
}
