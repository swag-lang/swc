#assert(0b11 == 0b0000000000011)
#assert(true == true)
#assert("true" == "true")
#assert(0b11 == 0x3)
#assert(0b1111 == 15)
#assert(0xfFFf == 65535)

#assert(0b11 == 0b10) // swc-expected-error {{sema_err_compiler_assert}}
#assert(true == false) // swc-expected-error {{sema_err_compiler_assert}}
#assert("truetrue" == "true" ++ "false") // swc-expected-error {{sema_err_compiler_assert}}
#assert(0xFFFFFFFF_FFFFFFFF_F == 0xFFFFFFFF_FFFFFFFF_F) // swc-expected-error {{sema_err_number_too_big}}
#assert(0b11111111111111111111111111111111_111111111111111111111111111111110 == 0b11111111111111111111111111111111_111111111111111111111111111111110)  // swc-expected-error {{sema_err_number_too_big}}

#assert(0xA == 10)
#assert(0b1010 == 10)
#assert(1.0 == 1)
#assert(1.0'f32 == 1)
#assert("hello" != "world")