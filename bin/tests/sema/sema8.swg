#assert(1.0 + 2.5 == 3.5)
#assert(1 + 2.5 == 3.5)
#assert(1 + 1.0 + 1 == 3.0)
#assert(2.0 - 1.0 == 1.0)
#assert(1.0 * 2.0 == 2.0)
#assert(2.0 / 1.0 == 2.0)
#assert(-1.0 * -1.0 == 1.0)

#assert(1's32 + 1 == 2)
#assert(1 + 1 == 2)
#assert(2'u32 * 2 == 4)
#assert(2 * 2 == 4)
#assert(4 / 2 == 2)
#assert(4'u32 / 2 == 2)

#print(1.0 / 0.0)   // swc-expected-error {{sema_err_division_zero}}
#print(255'u8 + 1)  // swc-expected-error {{sema_err_integer_overflow}}
#print(255'u8 / 0)  // swc-expected-error {{sema_err_division_zero}}