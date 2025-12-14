#assert(1 + 1 == 2)
#assert(1's32 + 1 == 2)
#assert(1's8 + 1 == 2)
#assert(1's16 + 1 == 2)
#assert(1's64 + 1 == 2)
#assert(1'u32 + 1 == 2)
#assert(1'u8 + 1 == 2)
#assert(1'u16 + 1 == 2)
#assert(1'u64 + 1 == 2)
#assert(127's8 + 0 == 127)
#assert(32767's16 + 0 == 32767)
#assert(2147483647's32 + 0 == 2147483647)
#assert(9223372036854775807's64 + 0 == 9223372036854775807)
#assert(255'u8 + 0 == 255)
#assert(65535'u16 + 0 == 65535)
#assert(4294967295'u32 + 0 == 4294967295)
#assert(18446744073709551615'u64 + 0 == 18446744073709551615'u64)

#assert(2 - 1 == 1)
#assert(2's32 - 1 == 1)
#assert(2's8 - 1 == 1)
#assert(2's16 - 1 == 1)
#assert(2's64 - 1 == 1)
#assert(2'u32 - 1 == 1)
#assert(2'u8 - 1 == 1)
#assert(2'u16 - 1 == 1)
#assert(2'u64 - 1 == 1)
#assert(0 - 2 == -2)
#assert(0's32 - 2 == -2)
#assert(0's8 - 2 == -2)
#assert(0's16 - 2 == -2)
#assert(0's64 - 2 == -2)
#assert(10'u16 - 3 == 7)
#assert(10'u8 - 3 == 7)
#assert(10'u32 - 3 == 7)
#assert(10'u64 - 3 == 7)
#assert(2 - 4 == -2)

#assert(2 * 2 == 4)
#assert(2's32 * 2 == 4)
#assert(2's8 * 2 == 4)
#assert(2's16 * 2 == 4)
#assert(2's64 * 2 == 4)
#assert(2'u32 * 2 == 4)
#assert(2'u8 * 2 == 4)
#assert(2'u16 * 2 == 4)
#assert(2'u64 * 2 == 4)
#assert(3's16 * 4 == 12)
#assert(3's8 * 4 == 12)
#assert(3's32 * 4 == 12)
#assert(3's64 * 4 == 12)
#assert(3'u8 * 4 == 12)
#assert(3'u16 * 4 == 12)
#assert(3'u32 * 4 == 12)
#assert(3'u64 * 4 == 12)

#assert(4 / 2 == 2)
#assert(4's32 / 2 == 2)
#assert(4's8 / 2 == 2)
#assert(4's16 / 2 == 2)
#assert(4's64 / 2 == 2)
#assert(4'u32 / 2 == 2)
#assert(4'u8 / 2 == 2)
#assert(4'u16 / 2 == 2)
#assert(4'u64 / 2 == 2)
#assert(-4's32 / 2 == -2)
#assert(-4's8 / 2 == -2)
#assert(-4's16 / 2 == -2)
#assert(-4's64 / 2 == -2)

#print(127's8 + 1)      // swc-expected-error {{sema_err_integer_overflow}}
#print(255'u8 + 1)      // swc-expected-error {{sema_err_integer_overflow}}
#print(0'u8 - 1)        // swc-expected-error {{sema_err_integer_overflow}}
#print(-128's8 - 1)     // swc-expected-error {{sema_err_integer_overflow}}
#print(32767's16 * 2)   // swc-expected-error {{sema_err_integer_overflow}}
#print(65535'u16 * 2)   // swc-expected-error {{sema_err_integer_overflow}}

#print(1 / 0)           // swc-expected-error {{sema_err_division_zero}}
#print(1's8 / 0)        // swc-expected-error {{sema_err_division_zero}}
#print(1's16 / 0)       // swc-expected-error {{sema_err_division_zero}}
#print(1's32 / 0)       // swc-expected-error {{sema_err_division_zero}}
#print(1's64 / 0)       // swc-expected-error {{sema_err_division_zero}}
#print(1'u8 / 0)        // swc-expected-error {{sema_err_division_zero}}
#print(1'u16 / 0)       // swc-expected-error {{sema_err_division_zero}}
#print(1'u32 / 0)       // swc-expected-error {{sema_err_division_zero}}
#print(1'u64 / 0)       // swc-expected-error {{sema_err_division_zero}}
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
#assert(1'u8 | 2'u8 == 3'u8)
#assert(1'u16 | 2'u16 == 3'u16)
#assert(1'u32 | 2'u32 == 3'u32)
#assert(1'u64 | 2'u64 == 3'u64)
#assert(1'u8 & 2'u8 == 0'u8)
#assert(1'u16 & 2'u16 == 0'u16)
#assert(1'u32 & 2'u32 == 0'u32)
#assert(1'u64 & 2'u64 == 0'u64)
#assert(1'u8 ^ 1'u8 == 0'u8)
#assert(1'u16 ^ 1'u16 == 0'u16)
#assert(1'u32 ^ 1'u32 == 0'u32)
#assert(1'u64 ^ 1'u64 == 0'u64)
#assert(0xFF'u8 & 0x01'u8 == 1)
#assert(0b1010 ^ 0b0110 == 0b1100)
#assert(0b1111 | 0b0000 == 0b1111)

#assert(1 << 1 == 2)
#assert(1's32 << 1 == 2)
#assert(1's8 << 1 == 2)
#assert(1's16 << 1 == 2)
#assert(1's64 << 1 == 2)
#assert(1'u32 << 1 == 2)
#assert(1'u8  << 1 == 2)
#assert(1'u16 << 1 == 2)
#assert(1'u64 << 1 == 2)
#assert(1'u8  << 7 == 128)

#assert(8 >> 1 == 4)
#assert(8's32 >> 1 == 4)
#assert(8's8 >> 1 == 4)
#assert(8's16 >> 1 == 4)
#assert(8's64 >> 1 == 4)
#assert(8'u32 >> 1 == 4)
#assert(8'u8  >> 1 == 4)
#assert(8'u16 >> 1 == 4)
#assert(8'u64 >> 1 == 4)
#assert(1'u8  >> 1 == 0)
#assert(2's8  >> 1 == 1)
#assert(1's8  >> 1 == 0)
#assert(-2's8 >> 1 == -1)
#assert(-128's8 >> 1 == -64)
#assert(255'u8 >> 1 == 127)
#assert(128'u8 >> 1 == 64)

#assert(1'u8  >> 20 == 0)
#assert(0'u16 >> 99 == 0)
#assert(0'u32 >> 99 == 0)
#assert(0'u64 >> 99 == 0)
#assert((-1's8) >> 20 == -1)
#assert((-1's16) >> 20 == -1)
#assert((-1's32) >> 20 == -1)
#assert((-1's64) >> 20 == -1)
#assert((-5's32) >> 100 == -1)
#assert((-5's64) >> 100 == -1)
#assert(5's32 >> 100 == 0)
#assert(5's64 >> 100 == 0)

#assert(1'u8 << 8 == 0)
#assert(1'u8 << 20 == 0)
#assert(1'u16 << 16 == 0)
#assert(1'u16 << 99 == 0)
#assert(1'u32 << 32 == 0)
#assert(1'u32 << 99 == 0)
#assert(1'u64 << 64 == 0)
#assert(1'u64 << 99 == 0)
#assert(5's8 << 8 == 0)
#assert(5's16 << 16 == 0)
#assert(5's32 << 32 == 0)
#assert(5's64 << 64 == 0)
#assert((-1's8) << 8 == 0)
#assert((-1's16) << 16 == 0)
#assert((-1's32) << 32 == 0)
#assert((-1's64) << 64 == 0)

#assert(3 % 4 == 3)
#assert(-7 % 3 == -1)
#assert(7 % -3 == 1)
#assert(-7 % -3 == -1)
#assert(0 % 5 == 0)
#print(5 % 0) // swc-expected-error {{sema_err_division_zero}}
#assert(10 % 3 == 1)
#assert(10's8 % 3 == 1)
#assert(10's16 % 3 == 1)
#assert(10's32 % 3 == 1)
#assert(10's64 % 3 == 1)
#assert(10'u8 % 3 == 1)
#assert(10'u16 % 3 == 1)
#assert(10'u32 % 3 == 1)
#assert(10'u64 % 3 == 1)
#assert(10'u32 % 3'u32 == 1)
#assert(10'u64 % 3'u64 == 1)

#assert(1.0 << 1)   // swc-expected-error {{sema_err_binary_operand_type}}
#assert(true >> 1)  // swc-expected-error {{sema_err_binary_operand_type}}
#assert(true & 1)   // swc-expected-error {{sema_err_binary_operand_type}}
#assert(true | 1)   // swc-expected-error {{sema_err_binary_operand_type}}
#assert(true ^ 1)   // swc-expected-error {{sema_err_binary_operand_type}}

#assert(1 << -1)    // swc-expected-error {{sema_err_negative_shift}}
#assert(1 >> -1)    // swc-expected-error {{sema_err_negative_shift}}

#print(-128's8 / -1)                    // swc-expected-error {{sema_err_integer_overflow}}
#print(-32768's16 / -1)                 // swc-expected-error {{sema_err_integer_overflow}}
#print(-2147483648's32 / -1)            // swc-expected-error {{sema_err_integer_overflow}}
#print(-9223372036854775808's64 / -1)   // swc-expected-error {{sema_err_integer_overflow}}
