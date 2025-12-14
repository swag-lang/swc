#assert(0b11 == 0b0000000000011)
#assert(0b0 == 0b0000)
#assert(0b1 == 0b0001)
#assert(0b101010 == 0b10_1010)
#assert(0b1111_0000 == 0b11110000)

#assert(true == true)
#assert(false == false)
#assert(true != false)
#assert(!(true == false))

#assert("true" == "true")
#assert("" == "")
#assert("a" ++ "b" == "ab")
#assert("hello" != "world")
#assert("a" != "b")

#assert(0b11 == 0x3)
#assert(0b1111 == 15)
#assert(0b1111'u8 == 15'u8)
#assert(15's16 == 0b1111)
#assert(0xfFFf == 65535)
#assert(0xFFFF == 65535)
#assert(0x0000_FFFF == 65535)
#assert(0xFF == 255)
#assert(0x0 == 0)
#assert(0x1 == 1)
#assert(0xA == 10)
#assert(0b1010 == 10)
#assert(0b1010'u16 == 10'u16)
#assert(10's32 == 0xA)

#assert(1.0 == 1)
#assert(1.0'f32 == 1)
#assert(1.0'f64 == 1)
#assert(0.0 == 0)
#assert(-0.0 == 0)
#assert(-1.0 == -1)
#assert(2.5 == 2.5)
#assert(2.5'f32 == 2.5'f32)
#assert(2.5'f64 == 2.5'f64)

#assert('a' == 'a')
#assert('a' != 'b')
#assert('0' != '1')
#assert('\n' == '\n')

#assert(0xFFFFFFFF_FFFFFFFF_F == 0xFFFFFFFF_FFFFFFFF_F)
#assert(0b11111111111111111111111111111111_111111111111111111111111111111110 == 0b11111111111111111111111111111111_111111111111111111111111111111110)
#assert(0xFFFF_FFFF == 0b11111111111111111111111111111111)
#assert(0xDEAD_BEEF == 0xDEAD_BEEF)
#assert(0b1101_1110_1010_1101_1011_1110_1110_1111 == 0xDEAD_BEEF)

#assert(0b11 == 0b10) // swc-expected-error {{sema_err_compiler_assert}}
#assert(true == false) // swc-expected-error {{sema_err_compiler_assert}}
#assert("truetrue" == "true" ++ "false") // swc-expected-error {{sema_err_compiler_assert}}
#assert("" == " ") // swc-expected-error {{sema_err_compiler_assert}}
#assert('a' == 'b') // swc-expected-error {{sema_err_compiler_assert}}

#print(0xFFFFFFFF_FFFFFFFF_F'u64) // swc-expected-error {{sema_err_literal_overflow}}
#print(0b11111111111111111111111111111111_111111111111111111111111111111110'u64) // swc-expected-error {{sema_err_literal_overflow}}
#print(0x1_0000_0000_0000_0000'u64) // swc-expected-error {{sema_err_literal_overflow}}
#print(0b1_00000000000000000000000000000000000000000000000000000000000000000'u64) // swc-expected-error {{sema_err_literal_overflow}}
