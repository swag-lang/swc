#global private

#[Swag.NoInline]
func byteShift8(a: u64)->u64 => (a & 255) << 8

#[Swag.NoInline]
func byteShift24(a: u64)->u64 => (a & 255) << 24

#[Swag.NoInline]
func byteShift25(a: u64)->u64 => (a & 255) << 25

#[Swag.NoInline]
func wordShift16(a: u64)->u64 => (a & 65535) << 16

#[Swag.NoInline]
func wordShift17(a: u64)->u64 => (a & 65535) << 17

#[Swag.NoInline]
func byteShift0(a: u64)->u64 => (a & 255) << 0

#test
{
    let values = [0'u64, 1, 127, 128, 255, 256, 32768, 65535, 0xFFFFFFFFFFFFFFFF]
    for value in values
    {
        let lowByte = value & 255
        let lowWord = value & 65535
        Swag.assert(byteShift8(value) == lowByte * 256)
        Swag.assert(byteShift24(value) == lowByte * 0x1000000)
        Swag.assert(byteShift25(value) == lowByte * 0x2000000)
        Swag.assert(wordShift16(value) == lowWord * 65536)
        Swag.assert(wordShift17(value) == lowWord * 131072)
        Swag.assert(byteShift0(value) == lowByte)
    }
}
