#global internal

#assert(1.0 + 2.5 == 3.5)
#assert(1.0'f32 + 2.5'f32 == 3.5'f32)
#assert(1.0'f64 + 2.5'f64 == 3.5'f64)

#assert(1 + 2.5 == 3.5)
#assert(1'u8 + 2.5 == 3.5)
#assert(1's8 + 2.5 == 3.5)
#assert(1'u16 + 2.5 == 3.5)
#assert(1's16 + 2.5 == 3.5)
#assert(1'u32 + 2.5 == 3.5)
#assert(1's32 + 2.5 == 3.5)
#assert(1'u64 + 2.5 == 3.5)
#assert(1's64 + 2.5 == 3.5)

#assert(1 + 1.0 + 1 == 3.0)
#assert(1'u32 + 1.0 + 1'u32 == 3.0)
#assert(1's32 + 1.0 + 1's32 == 3.0)
#assert(1.0'f32 + 1.0'f32 + 1.0'f32 == 3.0'f32)
#assert(1.0'f64 + 1.0'f64 + 1.0'f64 == 3.0'f64)

#assert(2.0 - 1.0 == 1.0)
#assert(2.0'f32 - 1.0'f32 == 1.0'f32)
#assert(2.0'f64 - 1.0'f64 == 1.0'f64)

#assert(1.0 * 2.0 == 2.0)
#assert(1.0'f32 * 2.0'f32 == 2.0'f32)
#assert(1.0'f64 * 2.0'f64 == 2.0'f64)

#assert(2.0 / 1.0 == 2.0)
#assert(2.0'f32 / 1.0'f32 == 2.0'f32)
#assert(2.0'f64 / 1.0'f64 == 2.0'f64)

#assert(-1.0 * -1.0 == 1.0)
#assert(-1.0'f32 * -1.0'f32 == 1.0'f32)
#assert(-1.0'f64 * -1.0'f64 == 1.0'f64)

#assert(1.0 + 1.0 == 2.0)
#assert(0.5 + 0.25 == 0.75)
#assert(2.5 + 0.0 == 2.5)
#assert(1.0'f32 + 1.0'f32 == 2.0'f32)
#assert(0.5'f32 + 0.25'f32 == 0.75'f32)
#assert(2.5'f32 + 0.0'f32 == 2.5'f32)
#assert(1.0'f64 + 1.0'f64 == 2.0'f64)
#assert(0.5'f64 + 0.25'f64 == 0.75'f64)
#assert(2.5'f64 + 0.0'f64 == 2.5'f64)

#assert(2.0 - 1.0 == 1.0)
#assert(1.5 - 0.25 == 1.25)
#assert(0.0 - 2.0 == -2.0)
#assert(2.0'f32 - 1.0'f32 == 1.0'f32)
#assert(1.5'f32 - 0.25'f32 == 1.25'f32)
#assert(0.0'f32 - 2.0'f32 == -2.0'f32)
#assert(2.0'f64 - 1.0'f64 == 1.0'f64)
#assert(1.5'f64 - 0.25'f64 == 1.25'f64)
#assert(0.0'f64 - 2.0'f64 == -2.0'f64)

#assert(2.0 * 2.0 == 4.0)
#assert(0.5 * 4.0 == 2.0)
#assert(-1.5 * 2.0 == -3.0)
#assert(2.0'f32 * 2.0'f32 == 4.0'f32)
#assert(0.5'f32 * 4.0'f32 == 2.0'f32)
#assert(-1.5'f32 * 2.0'f32 == -3.0'f32)
#assert(2.0'f64 * 2.0'f64 == 4.0'f64)
#assert(0.5'f64 * 4.0'f64 == 2.0'f64)
#assert(-1.5'f64 * 2.0'f64 == -3.0'f64)

#assert(4.0 / 2.0 == 2.0)
#assert(1.5 / 0.5 == 3.0)
#assert(-3.0 / 1.5 == -2.0)
#assert(4.0'f32 / 2.0'f32 == 2.0'f32)
#assert(1.5'f32 / 0.5'f32 == 3.0'f32)
#assert(-3.0'f32 / 1.5'f32 == -2.0'f32)
#assert(4.0'f64 / 2.0'f64 == 2.0'f64)
#assert(1.5'f64 / 0.5'f64 == 3.0'f64)
#assert(-3.0'f64 / 1.5'f64 == -2.0'f64)

#assert(0.0 + 0.0 == 0.0)
#assert(-0.0 + 0.0 == 0.0)
#assert(5.0 - 5.0 == 0.0)
#assert(10.0 / 2.0 == 5.0)
#assert(0.0'f32 + 0.0'f32 == 0.0'f32)
#assert(-0.0'f32 + 0.0'f32 == 0.0'f32)
#assert(5.0'f32 - 5.0'f32 == 0.0'f32)
#assert(10.0'f32 / 2.0'f32 == 5.0'f32)
#assert(0.0'f64 + 0.0'f64 == 0.0'f64)
#assert(-0.0'f64 + 0.0'f64 == 0.0'f64)
#assert(5.0'f64 - 5.0'f64 == 0.0'f64)
#assert(10.0'f64 / 2.0'f64 == 5.0'f64)

#assert(0.1 + 0.2 == 0.3)
#assert(0.1'f32 + 0.2'f32 == 0.3'f32)
#assert(0.1'f64 + 0.2'f64 == 0.3'f64)

#assert(1.0 * 1.000000000 == 1.0)
#assert(1.0'f32 * 1.000000000'f32 == 1.0'f32)
#assert(1.0'f64 * 1.000000000'f64 == 1.0'f64)

#print(1.0 / 0.0)      // swc-expected-error {{sema_err_division_zero}}
#print(1.0'f32 / 0.0)  // swc-expected-error {{sema_err_division_zero}}
#print(1.0'f64 / 0.0)  // swc-expected-error {{sema_err_division_zero}}
#print(-1.0 / 0.0)     // swc-expected-error {{sema_err_division_zero}}
#print(-1.0'f32 / 0.0) // swc-expected-error {{sema_err_division_zero}}
#print(-1.0'f64 / 0.0) // swc-expected-error {{sema_err_division_zero}}
#print(0.0 / 0.0)      // swc-expected-error {{sema_err_division_zero}}
#print(0.0'f32 / 0.0)  // swc-expected-error {{sema_err_division_zero}}
#print(0.0'f64 / 0.0)  // swc-expected-error {{sema_err_division_zero}}

#assert(1.0 - 1.0 == 0.0)
#assert(1.0 * 0.0 == 0.0)
#assert(1.0 / 1.0 == 1.0)
#assert(-1.0 / 1.0 == -1.0)
#assert(0.0 / 1.0 == 0.0)
#assert(1.0'f32 - 1.0'f32 == 0.0'f32)
#assert(1.0'f32 * 0.0'f32 == 0.0'f32)
#assert(1.0'f32 / 1.0'f32 == 1.0'f32)
#assert(-1.0'f32 / 1.0'f32 == -1.0'f32)
#assert(0.0'f32 / 1.0'f32 == 0.0'f32)
#assert(1.0'f64 - 1.0'f64 == 0.0'f64)
#assert(1.0'f64 * 0.0'f64 == 0.0'f64)
#assert(1.0'f64 / 1.0'f64 == 1.0'f64)
#assert(-1.0'f64 / 1.0'f64 == -1.0'f64)
#assert(0.0'f64 / 1.0'f64 == 0.0'f64)

#assert(1.0'f32 + 2.0'f64 == 3.0)
#assert(1.0'f32 + 2.0'f64 == 3.0'f64)
#assert(1.0'f64 + 2.0'f32 == 3.0)
#assert(1.0'f64 + 2.0'f32 == 3.0'f64)

#assert(0.0 == -0.0)
#assert(0.0'f32 == -0.0'f32)
#assert(0.0'f64 == -0.0'f64)
#assert(-5.0 * 0.0 == 0.0)
#assert(-5.0'f32 * 0.0'f32 == 0.0'f32)
#assert(-5.0'f64 * 0.0'f64 == 0.0'f64)
#assert(0.0 <= -0.0)
#assert(0.0'f32 <= -0.0'f32)
#assert(0.0'f64 <= -0.0'f64)
#assert(-0.0 >= 0.0)
#assert(-0.0'f32 >= 0.0'f32)
#assert(-0.0'f64 >= 0.0'f64)
