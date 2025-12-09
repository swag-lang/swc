#assert(cast(s8) 1 == 1)
#assert(cast(s8) -1 == -1)
#assert(cast(s32) 0 == 0)

#assert(cast(s32) 0 == 0)
#assert(cast(u8) 1 == 1)
#assert(cast(u16) 65535 == 65535)
#assert(cast(f32) 45'u8 == 45)
#assert(cast(f32) 45'u16 == 45)
#assert(cast(f32) -45's8 == -45)
#assert(cast(s32) 3.9 == 3)
#assert(cast(s32) -3.9 == -3)
#assert(cast(u8) 255'u16 == 255)

#assert(cast(f64) 123456789'u32 == 123456789)
#assert(cast(f64) -123456789's32 == -123456789)
#assert(cast(s64) 9223372036854775807'u64 == 9223372036854775807)
#assert(cast(u64) 18446744073709551615'u64 == 18446744073709551615)
#assert(cast(f64) 1.7976931348623157e+308'f64 == 1.7976931348623157e+308)
#assert(cast(u16) 65535'u32 == 65535)
#assert(cast(s16) -32768's32 == -32768)
#assert(cast(u32) 4294967295'u64 == 4294967295)
#assert(cast(s32) -2147483648's64 == -2147483648)
#assert(cast(f32) 0.0'f32 == 0.0)
#assert(cast(f64) -0.0'f64 == -0.0)
#assert(cast(u8) 0'u8 == 0)
#assert(cast(s8) -128's8 == -128)
#assert(cast(rune) 'A' == 'A')
#assert(cast(rune) 'é' == 'é')
#assert(cast(rune) '☃' == '☃')
#assert(cast(rune) '😀' == '😀')
#assert(cast(bool) true == true)
#assert(cast(bool) false == false)
#assert(cast(bool) (1'u8 != 0'u8) == true)
#assert(cast(bool) (0'u8 != 0'u8) == false)
#assert(cast(s32) cast(f32) 123.456'f32 == 123's32)
#assert(cast(s64) cast(f64) -9223372036854775808.0'f64 == -9223372036854775808's64)
#assert(cast(f64) cast(s64) 9223372036854775807's64 == 9223372036854775807.0'f64)
#assert(cast(rune) cast(u32) 0x1F600'u32 == '😀')
#assert(cast(f32) cast(s32) -123's32 == -123)

#assert(cast(f64) 65535'u16 == 65535)
#assert(cast(s16) -32768's16 == -32768)
#assert(cast(u32) 4294967295'u32 == 4294967295)
#assert(cast(s32) -2147483648's32 == -2147483648)
#assert(cast(f32) 0.0'f32 == 0.0)
#assert(cast(f64) -0.0'f64 == -0.0)
#assert(cast(u8) 0'u8 == 0)
#assert(cast(s8) -128's8 == -128)

#assert(cast(u8) -1's8 == 255'u8)               // swc-expected-error {{sema_err_signed_unsigned}}
#assert(cast(u8) -257's32 == 255'u8)            // swc-expected-error {{sema_err_signed_unsigned}}
#assert(cast(u8) -256's32 == 0'u8)              // swc-expected-error {{sema_err_signed_unsigned}}

#assert(cast(s8) 255'u8 == -1's8)               // swc-expected-error {{sema_err_signed_unsigned}}
#assert(cast(s8) 128'u32 == -128's8)            // swc-expected-error {{sema_err_signed_unsigned}}
#assert(cast(s8) 255'u32 == -1's8)              // swc-expected-error {{sema_err_signed_unsigned}}

#assert(cast(u8) 256'u32 == 0'u8)               // swc-expected-error {{sema_err_literal_overflow}}
#assert(cast(u8) 257'u32 == 1'u8)               // swc-expected-error {{sema_err_literal_overflow}}
#assert(cast(u16) 65536'u32 == 0'u16)           // swc-expected-error {{sema_err_literal_overflow}}
#assert(cast(u32) 4294967296'u64 == 0'u32)      // swc-expected-error {{sema_err_literal_overflow}}
#assert(cast(s16) 65536'u32 == 0's16)           // swc-expected-error {{sema_err_literal_overflow}}
#assert(cast(s32) 4294967296'u64 == 0's32)      // swc-expected-error {{sema_err_literal_overflow}}
#assert(cast(u16) 65537'u32 == 1'u16)           // swc-expected-error {{sema_err_literal_overflow}}

 #assert(-1's8 == -1'f32)