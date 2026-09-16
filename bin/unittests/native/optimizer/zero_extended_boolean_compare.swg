#global private

#[Swag.NoInline]
func byteZero(a: u64)->u64 => cast(u64) ((a & 255) == 0)

#[Swag.NoInline]
func byteNotZero(a: u64)->u64 => cast(u64) ((a & 255) != 0)

#[Swag.NoInline]
func byteEqual(a: u64)->u32 => cast(u32) ((a & 255) == 127)

#[Swag.NoInline]
func byteLess(a: u64)->u64 => cast(u64) ((a & 255) < 128)

#[Swag.NoInline]
func wordAtLeast(a: u64)->u64 => cast(u64) ((a & 65535) >= 32768)

#[Swag.NoInline]
func wideImmediate(a: u64)->u64 => cast(u64) ((a & 255) < 256)

#[Swag.NoInline]
func preserveInput(a: u64)->u64 => a ^ byteZero(a)

#test
{
    let values = [0'u64, 1, 127, 128, 255, 256, 32768, 65535, 65536, 0xFFFFFFFFFFFFFFFF]
    for value in values
    {
        let byte = value % 256
        let word = value % 65536
        Swag.assert(byteZero(value) == (byte == 0 ? 1 : 0))
        Swag.assert(byteNotZero(value) == (byte != 0 ? 1 : 0))
        Swag.assert(byteEqual(value) == (byte == 127 ? 1 : 0))
        Swag.assert(byteLess(value) == (byte < 128 ? 1 : 0))
        Swag.assert(wordAtLeast(value) == (word >= 32768 ? 1 : 0))
        Swag.assert(wideImmediate(value) == 1)
        Swag.assert(preserveInput(value) == (value ^ (byte == 0 ? 1 : 0)))
    }
}
