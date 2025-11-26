#assert(0b11 == 0b10) // swc-expected-error {{sema_err_compiler_assert}}
#assert(0b11 == 0b0000000000011)
#assert(true == true)
#assert(true == false) // swc-expected-error {{sema_err_compiler_assert}}
#assert("true" == "true")
#assert("truetrue" == "true" ++ "true")
#assert("truetrue" == "true" ++ true)
#assert("truetrue" == "true" ++ "false") // swc-expected-error {{sema_err_compiler_assert}}
#assert(0b11 == 0x3)
#assert(0b1111 == 15)
#assert(0xfFFf == 65535)

// 64 bits overflow
#assert(0xFFFFFFFF_FFFFFFFF_F == 0xFFFFFFFF_FFFFFFFF_F) // swc-expected-error {{sema_err_number_too_big}}
#assert(0b11111111111111111111111111111111_111111111111111111111111111111110 == 0b11111111111111111111111111111111_111111111111111111111111111111110)  // swc-expected-error {{sema_err_number_too_big}}
