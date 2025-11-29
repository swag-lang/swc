#assert("truetrue" == "true" ++ "true")
#assert("truetrue" == "true" ++ true)
#assert(1 ++ 2 == "12")
#assert(1's32 ++ 2 == "12")

#assert(-1's32 ++ 0 == "-10")
#assert(-1234's32 ++ 0 == "-12340")

#assert(1 ++ @err == "12") // swc-expected-error {{sema_err_expr_not_const}}
#assert(@err ++ 1 == "12") // swc-expected-error {{sema_err_expr_not_const}}
