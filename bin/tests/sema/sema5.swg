#assert("truetrue" == "true" ++ "true")
#assert("truetrue" == "true" ++ true)
#assert(1 ++ 2 == "12")
#assert(1's32 ++ 2 == "12")

#print(-1's32)

#assert(1 ++ @err == "12") // swc-expected-error {{sema_err_expr_not_const}}
#assert(@err ++ 1 == "12") // swc-expected-error {{sema_err_expr_not_const}}
