#global private

#[Swag.NoInline]
func maskedByte(value: u64)->u64 => (value & 255) << 8

#[Swag.NoInline]
func maskedWord(value: u64)->u64 => (value & 65535) << 16

#[Swag.NoInline]
func signedByte(value: s8)->s64 => cast(s64, value)

#[Swag.NoInline]
func signedWord(value: s16)->s64 => cast(s64, value)

#[Swag.NoInline]
func unsignedWord(value: u16)->u64 => cast(u64, value)

#test
{
    Swag.require(maskedByte(0xFFFFFFFFFFFFFFFF) == 0xFF00)
    Swag.require(maskedByte(0x0123456789ABCDEF) == 0xEF00)
    Swag.require(maskedWord(0xFFFFFFFFFFFFFFFF) == 0xFFFF0000)
    Swag.require(maskedWord(0x0123456789ABCDEF) == 0xCDEF0000)
    Swag.require(signedByte(-128) == -128)
    Swag.require(signedByte(-1) == -1)
    Swag.require(signedByte(127) == 127)
    Swag.require(signedWord(-32768) == -32768)
    Swag.require(signedWord(32767) == 32767)
    Swag.require(unsignedWord(65535) == 65535)
}
