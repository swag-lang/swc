#assert(1.0 + 2.5 == 3.5)
#assert(1 + 2.5 == 3.5)
#assert(1 + 1.0 + 1 == 3.0)
#assert(2.0 - 1.0 == 1.0)
#assert(1.0 * 2.0 == 2.0)
#assert(2.0 / 1.0 == 2.0)
#assert(-1.0 * -1.0 == 1.0)

#assert(1.0 + 1.0 == 2.0)
#assert(0.5 + 0.25 == 0.75)
#assert(2.5 + 0.0 == 2.5)

#assert(2.0 - 1.0 == 1.0)
#assert(1.5 - 0.25 == 1.25)
#assert(0.0 - 2.0 == -2.0)

#assert(2.0 * 2.0 == 4.0)
#assert(0.5 * 4.0 == 2.0)
#assert(-1.5 * 2.0 == -3.0)

#assert(4.0 / 2.0 == 2.0)
#assert(1.5 / 0.5 == 3.0)
#assert(-3.0 / 1.5 == -2.0)

#assert(0.0 + 0.0 == 0.0)
#assert(-0.0 + 0.0 == 0.0)
#assert(5.0 - 5.0 == 0.0)
#assert(10.0 / 2.0 == 5.0)

#assert(0.1 + 0.2 == 0.3)
#assert(1.0 * 1.000000000 == 1.0)

#print(1.0 / 0.0)    // swc-expected-error {{sema_err_division_zero}}
#print(-1.0 / 0.0)   // swc-expected-error {{sema_err_division_zero}}
#print(0.0 / 0.0)    // swc-expected-error {{sema_err_division_zero}}

#assert(1.0 - 1.0 == 0.0)
#assert(1.0 * 0.0 == 0.0)
#assert(1.0 / 1.0 == 1.0)
#assert(-1.0 / 1.0 == -1.0)
#assert(0.0 / 1.0 == 0.0)
#assert(1.0'f32 + 2.0'f64 == 3.0)

#assert(0.0 == -0.0)
#assert(-5.0 * 0.0 == 0.0)
#assert(0.0 <= -0.0)
#assert(-0.0 >= 0.0)
