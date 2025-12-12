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
#print(1 / #wrap 4)             // swc-expected-error {{sema_err_modifier_unsupported}}
#print(1 / #bit 4)              // swc-expected-error {{sema_err_modifier_unsupported}}
#print(1 ++ #wrap 4)            // swc-expected-error {{sema_err_modifier_unsupported}}
#assert(1 ^ #wrap 0 == 1)       // swc-expected-error {{sema_err_modifier_unsupported}}
#assert(1 & #wrap 0 == 1)       // swc-expected-error {{sema_err_modifier_unsupported}}
#assert(1 | #wrap 0 == 1)       // swc-expected-error {{sema_err_modifier_unsupported}}

#assert(127's8 + #wrap 1 == -128)
#assert(127's8 + #prom 1 == 128)

#assert(1 | 2 == 3)
#assert(1 & 2 == 0)
#assert(1 & 1 == 1)
#assert(1 ^ 1 == 0)

#assert(1 ^ 0 == 1)

#assert(1 << 1 == 2)
#assert(1's32 << 1 == 2)
#assert(1'u32 << 1 == 2)
#assert(1'u8  << 1 == 2)
#assert(1'u8  << 7 == 128)

#assert(8 >> 1 == 4)
#assert(8's32 >> 1 == 4)
#assert(8'u32 >> 1 == 4)
#assert(8'u8  >> 1 == 4)
#assert(1'u8  >> 1 == 0)
#assert(2's8  >> 1 == 1)
#assert(1's8  >> 1 == 0)
#assert(-2's8 >> 1 == -1)
#assert(-128's8 >> 1 == -64)
#assert(255'u8 >> 1 == 127)
#assert(128'u8 >> 1 == 64)

#assert(1'u8  >> 20 == 0)
#assert(0'u16 >> 99 == 0)
#assert((-1's8) >> 20 == -1)
#assert((-5's32) >> 100 == -1)
#assert(5's32 >> 100 == 0)

#assert(1'u8 << 8 == 0)
#assert(1'u8 << 20 == 0)
#assert(5's8 << 8 == 0)
#assert((-1's8) << 8 == 0)

#assert(3 % 4 == 3)
#assert(-7 % 3 == -1)
#assert(7 % -3 == 1)
#assert(-7 % -3 == -1)
#assert(0 % 5 == 0)
#print(5 % 0) // swc-expected-error {{sema_err_division_zero}}
#assert(10 % 3 == 1)
#assert(10'u32 % 3'u32 == 1)

#assert(1.0 << 1)   // swc-expected-error {{sema_err_binary_operand_type}}
#assert(true >> 1)  // swc-expected-error {{sema_err_binary_operand_type}}
#assert(true & 1)   // swc-expected-error {{sema_err_binary_operand_type}}
#assert(true | 1)   // swc-expected-error {{sema_err_binary_operand_type}}
#assert(true ^ 1)   // swc-expected-error {{sema_err_binary_operand_type}}

#assert(1 << -1)    // swc-expected-error {{sema_err_negative_shift}}
#assert(1 >> -1)    // swc-expected-error {{sema_err_negative_shift}}

#assert(0xFF'u8 & 0x01'u8 == 1)
#assert(0b1010 ^ 0b0110 == 0b1100) // 10 ^ 6 == 12
#assert(0b1111 | 0b0000 == 0b1111) // 15 | 0 == 15