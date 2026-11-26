#global private

#assert(cast(s8, 1) == 1)
#assert(cast(s8, -1) == -1)
#assert(cast(s16, 0) == 0)
#assert(cast(s32, 0) == 0)
#assert(cast(s64, 0) == 0)
#assert(cast(u8, 1) == 1)
#assert(cast(u16, 65535) == 65535)
#assert(cast(u32, 0) == 0)
#assert(cast(u64, 0) == 0)

#assert(cast(f32, 45_u8) == 45)
#assert(cast(f32, 45_u16) == 45)
#assert(cast(f32, 45_u32) == 45)
#assert(cast(f32, 45_u64) == 45)
#assert(cast(f32, -45_s8) == -45)
#assert(cast(f32, -45_s16) == -45)
#assert(cast(f32, -45_s32) == -45)
#assert(cast(f32, -45_s64) == -45)

#assert(cast(f64, 123456789_u32) == 123456789)
#assert(cast(f64, 123456789_u64) == 123456789)
#assert(cast(f64, -123456789_s32) == -123456789)
#assert(cast(f64, -123456789_s64) == -123456789)

#assert(cast(s32, 3.9) == 3)
#assert(cast(s32, -3.9) == -3)
#assert(cast(s32, 3.9_f32) == 3)
#assert(cast(s32, -3.9_f32) == -3)
#assert(cast(s64, 3.9) == 3)
#assert(cast(s64, -3.9) == -3)

#assert(cast(u8, 255_u16) == 255)
#assert(cast(u16, 65535_u32) == 65535)
#assert(cast(u32, 4294967295_u64) == 4294967295)
#assert(cast(s16, -32768_s32) == -32768)
#assert(cast(s32, -2147483648_s64) == -2147483648)
#assert(cast(s64, -2147483648_s32) == -2147483648)

#assert(cast(s64, 9223372036854775807_u64) == 9223372036854775807)

#assert(cast(f32, 0.0_f32) == 0.0)
#assert(cast(f64, -0.0_f64) == -0.0)
#assert(cast(f32, 0.0) == 0.0)
#assert(cast(f64, 0.0) == 0.0)
#assert(cast(f64, -0.0) == -0.0)

#assert(cast(u8, 0_u8) == 0)
#assert(cast(u16, 0_u16) == 0)
#assert(cast(u32, 0_u32) == 0)
#assert(cast(u64, 0_u64) == 0)

#assert(cast(s8, -128_s8) == -128)
#assert(cast(s16, -32768_s16) == -32768)
#assert(cast(s32, -2147483648_s32) == -2147483648)
#assert(cast(s64, -9223372036854775808_s64) == -9223372036854775808)

#assert(cast(rune, 'A') == 'A')
#assert(cast(rune, 'é') == 'é')
#assert(cast(rune, '☃') == '☃')
#assert(cast(rune, '😀') == '😀')
#assert(cast(u32, 'A') == 65_u32)
#assert(cast(u32, '😀') == 0x1F600_u32)
#assert(cast(rune, 65_u32) == 'A')
#assert(cast(rune, 0x1F600_u32) == '😀')

#assert(cast(bool, true) == true)
#assert(cast(bool, false) == false)
#assert(cast(bool, (1_u8 != 0_u8)) == true)
#assert(cast(bool, (0_u8 != 0_u8)) == false)
#assert(cast(u8, true) == 1_u8)
#assert(cast(u8, false) == 0_u8)
#assert(cast(u16, true) == 1_u16)
#assert(cast(u16, false) == 0_u16)
#assert(cast(u32, true) == 1_u32)
#assert(cast(u32, false) == 0_u32)
#assert(cast(u64, true) == 1_u64)
#assert(cast(u64, false) == 0_u64)
#assert(cast(f32, true) == 1.0_f32)
#assert(cast(f32, false) == 0.0_f32)
#assert(cast(f64, true) == 1.0_f64)
#assert(cast(f64, false) == 0.0_f64)
#assert(cast(bool, 1_u8) == true)
#assert(cast(bool, 0_u8) == false)
#assert(cast(bool, 2_u8) == true)
#assert(cast(bool, 255_u8) == true)

#assert(cast(s32, cast(f32, 123.456_f32)) == 123_s32)
#assert(cast(s32, cast(f32, -123.75_f32)) == -123_s32)
#assert(cast(f32, cast(s32, -123_s32)) == -123)
#assert(cast(s64, cast(f64, 123.999_f64)) == 123_s64)
#assert(cast(s64, cast(f64, -123.999_f64)) == -123_s64)
#assert(cast(u16, cast(f32, 65535.0_f32)) == 65535_u16)
#assert(cast(f64, cast(s32, -2147483648_s32)) == -2147483648.0_f64)
#assert(cast(rune, cast(u32, 0x1F600_u32)) == '😀')

#assert(cast(f64, 65535_u16) == 65535)
#assert(cast(s16, -32768_s16) == -32768)
#assert(cast(u32, 4294967295_u32) == 4294967295)
#assert(cast(s32, -2147483648_s32) == -2147483648)
#assert(cast(f32, 0.0_f32) == 0.0)
#assert(cast(f64, -0.0_f64) == -0.0)
#assert(cast(u8, 0_u8) == 0)
#assert(cast(s8, -128_s8) == -128)

#assert(cast(s8, 127_s32) == 127)
#assert(cast(u8, 255_s32) == 255_u8)
#assert(cast(s16, -128_s32) == -128_s16)
#assert(cast(u16, 65535_u32) == 65535_u16)
#assert(cast(s32, 32767_s16) == 32767_s32)
#assert(cast(u32, 65535_u16) == 65535_u32)

#assert(cast(u64, 18446744073709551615_u64) == 18446744073709551615)

func semaTest001()
{
    var a: [4] u8
    var b = cast(string, a)
    discard b
    var c = cast(cstring, a)
    discard c
}

func semaTest002()
{
    var x: s32
    var a = cast([*] s32, &x)
    var b = cast(u64, a)
    discard b
}

func semaTest003()
{
    var a: [4] s32
    var s = cast([..] s32, a)
    #assert(#typeof(s) == [..] s32)
}

func semaTest004()
{
    var a: [4] u8
    var s = cast([..] u16, a)
    #assert(#typeof(s) == [..] u16)
}

func takeStringValue(value: string)->u64
{
    return value.count
}

func semaTest005()
{
    var text             = "abcd"
    var textRef: *string = &text
    let textValue        = cast(string, textRef[])
    let textSize         = takeStringValue(textRef[])

    #assert(#typeof(textValue) == string)
    #assert(#typeof(textSize) == u64)
    Swag.assert(textValue == "abcd")
    Swag.assert(textSize == 4_u64)
}
