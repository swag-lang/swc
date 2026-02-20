#global internal

#assert("truetrue" == "true" ++ "true")
#assert("truetrue" == "true" ++ true)
#assert("truefalse" == "true" ++ false)
#assert("falsetrue" == false ++ "true")
#assert("falsefalse" == false ++ false)

#assert(1 ++ 2 == "12")
#assert(1's32 ++ 2 == "12")
#assert(1's8 ++ 2 == "12")
#assert(1's16 ++ 2 == "12")
#assert(1's64 ++ 2 == "12")
#assert(1'u8 ++ 2 == "12")
#assert(1'u16 ++ 2 == "12")
#assert(1'u32 ++ 2 == "12")
#assert(1'u64 ++ 2 == "12")

#assert(-1's32 ++ 0 == "-10")
#assert(-1's8 ++ 0 == "-10")
#assert(-1's16 ++ 0 == "-10")
#assert(-1's64 ++ 0 == "-10")
#assert(-1234's32 ++ 0 == "-12340")
#assert(-1234's64 ++ 0 == "-12340")

#assert(0 ++ 0 == "00")
#assert(3 ++ 3 == "33")
#assert(10 ++ 20 == "1020")
#assert(255'u8 ++ 1 == "2551")
#assert(65535'u16 ++ 0 == "655350")

#assert(1.5645789'f32 ++ 0 == "1.56457890")
#assert(1.5645789'f64 ++ 0 == "1.56457889999999990")
#assert(0.0'f32 ++ 0 == "00")
#assert(0.0'f64 ++ 0 == "00")
#assert(-1.0'f32 ++ 0 == "-10")
#assert(-1.0'f64 ++ 0 == "-10")

#assert("123" == 1 ++ "23")
#assert("false-1" == false ++ -1)
#assert("true-1" == true ++ -1)
#assert("A" ++ "B" == "AB")
#assert("A" ++ "" == "A")
#assert("" ++ "B" == "B")
#assert("1" == 1 ++ "")
#assert("" ++ "" == "")
#assert('a' ++ 'a' == "aa")
#assert('A' ++ "" == "A")
#assert("" ++ 'Z' == "Z")
#assert('😀' ++ '😀' == "😀😀")

#assert(1 ++ @err == "12") // swc-expected-error {{sema_err_expr_not_const}}
#assert(@err ++ 1 == "12") // swc-expected-error {{sema_err_expr_not_const}}
#assert(@err ++ @err == "") // swc-expected-error {{sema_err_expr_not_const}}
