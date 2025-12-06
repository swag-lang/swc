#assert(1's32 + 1 == 2)
#assert(1 + 1 == 2)
#assert(2'u32 * 2 == 4)
#assert(2 * 2 == 4)
#assert(4 / 2 == 2)
#assert(4'u32 / 2 == 2)
#assert(2 - 4 == -2)

#assert(1 + 1 == 2)
#assert(1's32 + 1 == 2);
#assert(1'u32 + 1 == 2)
#assert(127's8 + 0 == 127)
#assert(255'u8 + 0 == 255)

#assert(2 - 1 == 1)
#assert(2's32 - 1 == 1)
#assert(2'u32 - 1 == 1)
#assert(0 - 2 == -2)
#assert(10'u16 - 3 == 7)

#assert(2 * 2 == 4)
#assert(2's32 * 2 == 4)
#assert(2'u32 * 2 == 4)
#assert(3's16 * 4 == 12)

#assert(4 / 2 == 2)
#assert(4's32 / 2 == 2)
#assert(4'u32 / 2 == 2)
#assert(-4's32 / 2 == -2)

#print(127's8 + 1)      // swc-expected-error {{sema_err_integer_overflow}}
#print(255'u8 + 1)      // swc-expected-error {{sema_err_integer_overflow}}
#print(0'u8 - 1)        // swc-expected-error {{sema_err_integer_overflow}}
#print(-128's8 - 1)     // swc-expected-error {{sema_err_integer_overflow}}
#print(32767's16 * 2)   // swc-expected-error {{sema_err_integer_overflow}}
#print(65535'u16 * 2)   // swc-expected-error {{sema_err_integer_overflow}}

#print(1 / 0)           // swc-expected-error {{sema_err_division_zero}}
#print(1's32 / 0)       // swc-expected-error {{sema_err_division_zero}}
#print(1'u32 / 0)       // swc-expected-error {{sema_err_division_zero}}
#print(0 / 0)           // swc-expected-error {{sema_err_division_zero}}

#print(127.0 + #wrap 1)         // swc-expected-error {{sema_err_modifier_only_integer}}
#print(127.0 + #prom 1)         // swc-expected-error {{sema_err_modifier_only_integer}}
#print(127.0 + #prom #wrap 1)   // swc-expected-error {{sema_err_modifier_only_integer}}
#print(1 / #wrap 4)             // swc1-expected-error {{sema_err_modifier_unsupported}}

#assert(127's8 + #wrap 1 == -128)
#assert(127's8 + #prom 1 == 128)
