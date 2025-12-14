#assert(true and true == true)
#assert(true and false == false)
#assert(!(false and true == false))
#assert(!(false and false == false))

#assert(true or true == true)
#assert(true or false == true)
#assert(false or true == true)
#assert(false or false == false)

#assert(!true == false)
#assert(!false == true)

#assert(true and true or false == (true and true) or false)
#assert(true and true or false == true)

#assert(false or true and false == false or (true and false))
#assert(false or true and false == false)

#assert(1 < 2 and 3 > 1 == true)
#assert(1 < 2 and 3 < 1 == false)

#assert(1 and 2)      // swc-expected-error {{sema_err_binary_operand_type}}
#assert(true and 1)   // swc-expected-error {{sema_err_binary_operand_type}}
#assert(1 or false)   // swc-expected-error {{sema_err_binary_operand_type}}
#assert(!"true")      // swc-expected-error {{sema_err_unary_operand_type}}

#assert(!1)
#assert(1 == 1 and 2 != 3 == true)
#assert(1 > 5 or 2 < 10 == true)