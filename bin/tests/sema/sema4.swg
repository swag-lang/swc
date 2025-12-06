#assert(1.5575 == 1.5575)
#assert(-1.5575 == -1.5575)
#assert(1.5575'f32 == 1.5575'f32)
#assert(1.5575'f64 == 1.5575'f64)

#assert(1'f32 == 1'f32)
#assert(1'f64 == 1'f64)

#assert(1 == 1'f32)
#assert(1 == 1'f64)
#assert(1'u32 == 1'f64)
#assert(1'f32 == 1'f64)
#assert(-1's8 == -1'f32)
#assert(-1's64 == -1'f64)
#assert(-1's16 == -1'f64)

#assert(1 != 0)
#assert(1's32 != 0's8)

#assert(1.0 < 2.0)
#assert(2.0 > 1.9)
#assert(2.0 >= 1.9)
#assert(1.0 >= 1.0)
#assert((1.0 <=> 2.0) == -1)
#assert((2.0 <=> 1.0) == 1)
#assert((1.0 <=> 1.0) == 0)
#assert((1.0'f32 <=> 2.0'f64) == -1)
#assert((2.0'f32 <=> 1.0'f64) == 1)
#assert((1.0'f32 <=> 1.0'f64) == 0)

#assert(1.5575'f32 == 1.557'f32) // swc-expected-error {{sema_err_compiler_assert}}
#assert(1.5575'f64 == 1.557'f64) // swc-expected-error {{sema_err_compiler_assert}}
#assert(1'f32 == 2'f32)          // swc-expected-error {{sema_err_compiler_assert}}
#assert(1'f64 == 2'f64)          // swc-expected-error {{sema_err_compiler_assert}}

#assert(1.0 < 0.5)               // swc-expected-error {{sema_err_compiler_assert}}
#assert((1.0 <=> 2.0) == 1)      // swc-expected-error {{sema_err_compiler_assert}}

#assert(1.0 + 2.5 == 3.5)
#assert(1 + 2.5 == 3.5)
#assert(1 + 1.0 + 1 == 3.0)
#assert(2.0 - 1.0 == 1.0)
#assert(1.0 * 2.0 == 2.0)
#assert(2.0 / 1.0 == 2.0)
#assert(-1.0 * -1.0 == 1.0)
#print(1.0 / 0.0) // swc-expected-error {{sema_err_division_zero}}

