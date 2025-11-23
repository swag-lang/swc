#assert(0b11 == 0b10) // swc-expected-error {{sema_err_compiler_assert}}
#assert(0b11 == 0b0000000000011)
#assert(true == true)
#assert(true == false) // swc-expected-error {{sema_err_compiler_assert}}
#assert("true" == "true")
#assert("truetrue" == "true" ++ "true")
#assert("truetrue" == "true" ++ true)
#assert("truetrue" == "true" ++ "false") // swc-expected-error {{sema_err_compiler_assert}}
#assert(0b11 == 0x3)