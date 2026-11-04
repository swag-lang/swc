#global if #os == Swag.TargetOs.Linux
#global private

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
func snprintf(buffer: [*] u8, size: u64, format: const [*] u8, args: ...)->s32

#[Swag.CallingConvention(.C)]
alias Print = func(buffer: [*] u8, size: u64, format: const [*] u8, args: ...)->s32

func checkPromotions(print: Print)
{
    var buffer: [128] u8
    var signed   = -7's8
    var unsigned = 65000'u16
    var real     = 1.25'f32
    var enabled  = true
    let count    = print(&buffer[0], buffer.count, "%d %d %.2f %d %s".buffer, signed, unsigned, real, enabled, "done".buffer)
    const Expected = "-7 65000 1.25 1 done"
    Swag.assert(count == cast(s32, Expected.count))
    Swag.assert(Swag.memcmp(&buffer[0], Expected.buffer, Expected.count) == 0)
}

#test
{
    checkPromotions(&snprintf)
    var buffer: [128] u8
    let count = snprintf(&buffer[0], buffer.count, "%d %d %d %d %d %d %d %d".buffer, 1, 2, 3, 4, 5, 6, 7, 8)
    const Expected = "1 2 3 4 5 6 7 8"
    Swag.assert(count == cast(s32, Expected.count))
    Swag.assert(Swag.memcmp(&buffer[0], Expected.buffer, Expected.count) == 0)
}

#test
{
    var buffer: [128] u8
    let count = snprintf(&buffer[0], buffer.count, "%.1f %.1f %.1f %.1f %.1f %.1f %.1f %.1f %.1f".buffer,
                         1.0'f32, 2.0'f64, 3.0'f32, 4.0'f64, 5.0'f32, 6.0'f64, 7.0'f32, 8.0'f64, 9.0'f32)
    const Expected = "1.0 2.0 3.0 4.0 5.0 6.0 7.0 8.0 9.0"
    Swag.assert(count == cast(s32, Expected.count))
    Swag.assert(Swag.memcmp(&buffer[0], Expected.buffer, Expected.count) == 0)

    let literalCount = snprintf(&buffer[0], buffer.count, "literal".buffer)
    Swag.assert(literalCount == 7)
    Swag.assert(Swag.memcmp(&buffer[0], "literal".buffer, 7) == 0)
}

#test
{
    var buffer: [128] u8
    let count = snprintf(&buffer[0], buffer.count, "%d/%.0f %d/%.0f %d/%.0f %d/%.0f %d/%.0f %d/%.0f %d/%.0f %d/%.0f %d/%.0f".buffer,
                         1, 11.0'f32, 2, 12.0'f32, 3, 13.0'f32, 4, 14.0'f32, 5, 15.0'f32,
                         6, 16.0'f32, 7, 17.0'f32, 8, 18.0'f32, 9, 19.0'f32)
    const Expected = "1/11 2/12 3/13 4/14 5/15 6/16 7/17 8/18 9/19"
    Swag.assert(count == cast(s32, Expected.count))
    Swag.assert(Swag.memcmp(&buffer[0], Expected.buffer, Expected.count) == 0)
}
