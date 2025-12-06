#assert(+1 == 1)
#assert(+1 == +1)
#assert(125 == +125)

#assert(~0 == -1)
#assert(~1 == -2)
#assert(~2 == -3)
#assert(~255 == -256)
#assert(~(-1) == 0)

#assert(~true) // swc-expected-error {{sema_err_unary_operand_type}}
#assert(~"true") // swc-expected-error {{sema_err_unary_operand_type}}