#assert("truetrue" == "true" ++ "true")
#assert("truetrue" == "true" ++ true)
#assert(1 ++ 2 == "12")
#assert(1's32 ++ 2 == "12")

#assert(-1's32 ++ 0 == "-10")
#assert(-1234's32 ++ 0 == "-12340")

#assert(1 ++ @err == "12") // swc-expected-error {{sema_err_expr_not_const}}
#assert(@err ++ 1 == "12") // swc-expected-error {{sema_err_expr_not_const}}

#assert(1.5645789'f32 ++ 0 == "1.56457890")
#assert(1.5645789'f64 ++ 0 == "1.56457889999999990")

#print("toto")