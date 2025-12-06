#assert(1.0 + 2.5 == 3.5)
#assert(1 + 2.5 == 3.5)
#assert(1 + 1.0 + 1 == 3.0)
#assert(2.0 - 1.0 == 1.0)
#assert(1.0 * 2.0 == 2.0)
#assert(2.0 / 1.0 == 2.0)
#assert(-1.0 * -1.0 == 1.0)
#print(1.0 / 0.0) // swc-expected-error {{sema_err_division_zero}}

#assert(1's32 + 1 == 2)