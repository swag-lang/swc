#assert(12's8 == 12's8)
#assert(12's16 == 12's16)
#assert(12's32 == 12's32)
#assert(12's64 == 12's64)

#assert(12'u8 == 12'u8)
#assert(12'u16 == 12'u16)
#assert(12'u32 == 12'u32)
#assert(12'u64 == 12'u64)

#assert(127's8  == 127's8)
#assert(255'u8 == 255'u8)
#assert(32767's16  == 32767's16)
#assert(65535'u16 == 65535'u16)
#assert(4294967295'u32 == 4294967295'u32)

#assert(-127's8 == -127's8)
#assert(-127 == -127)

#assert(-128's8 == -128's8)
#assert(-32768's16 == -32768's16)

#assert(1's8 == 1)
#assert(1's16 == 1)
#assert(1's32 == 1)
#assert(1's64 == 1)
#assert(1'u8 == 1)
#assert(1'u16 == 1)
#assert(1'u32 == 1)
#assert(1'u64 == 1)

#assert(1's8  == 1's16)
#assert(1's8  == 1's32)
#assert(1's8  == 1's64)
#assert(1's16 == 1's32)
#assert(1's16 == 1's64)
#assert(1's32 == 1's64)
#assert(42 == 42's8)
#assert(42 == 42's16)
#assert(42 == 42's32)
#assert(42 == 42's64)
#assert(42 == 42'u8)
#assert(42 == 42'u16)
#assert(42 == 42'u32)
#assert(42 == 42'u64)
#assert(10's8 == 10'u8)
#assert(100's16 == 100'u16)
#assert(127's8 == 127's16)
#assert(255'u8 == 255'u16)
#assert(32767's16 == 32767's32)
#assert(65535'u16 == 65535'u32)
#assert(1's8 == 1'u64)

#assert(1 < 2)
#assert(1 <= 2)
#assert(1 <= 1)
#assert(2 > 1)
#assert(2 >= 1)
#assert(2 >= 2)
#assert((1 <=> 2) == -1)
#assert((2 <=> 1) == 1)
#assert((1 <=> 1) == 0)

#assert(128's8  == 0's8)            // swc-expected-error {{sema_err_literal_overflow}}
#assert(256'u8 == 0'u8)             // swc-expected-error {{sema_err_literal_overflow}}
#assert(32768's16  == 0's16)        // swc-expected-error {{sema_err_literal_overflow}}
#assert(65536'u16 == 0'u16)         // swc-expected-error {{sema_err_literal_overflow}}
#assert(4294967296'u32 == 0'u32)    // swc-expected-error {{sema_err_literal_overflow}}

#assert(-127'u8 == -127'u8)         // swc-expected-error {{sema_err_signed_unsigned}}
#assert(-127'u16 == -127'u16)       // swc-expected-error {{sema_err_signed_unsigned}}
#assert(-127'u32 == -127'u32)       // swc-expected-error {{sema_err_signed_unsigned}}
#assert(-127'u64 == -127'u64)       // swc-expected-error {{sema_err_signed_unsigned}}

#assert(-"127'u8" == -"127'u8")     // swc-expected-error {{sema_err_unary_operand_type}}
#assert(-true == -true)             // swc-expected-error {{sema_err_unary_operand_type}}
#assert(true <=> 0)                 // swc-expected-error {{sema_err_binary_operand_type}}
#assert("true" <=> 0)               // swc-expected-error {{sema_err_binary_operand_type}}
#assert(0 <=> true)                 // swc-expected-error {{sema_err_binary_operand_type}}
#assert(0 <=> "0")                  // swc-expected-error {{sema_err_binary_operand_type}}

#assert(-1's8 == 0'u8)              // swc-expected-error {{sema_err_signed_unsigned}}
#assert((-1's16 == 0'u16))          // swc-expected-error {{sema_err_signed_unsigned}}
#assert(255'u8 == 255's8)           // swc-expected-error {{sema_err_literal_overflow}}
#assert(65535'u16 == 65535's16)     // swc-expected-error {{sema_err_literal_overflow}}
#assert(200'u8 == 200's8)           // swc-expected-error {{sema_err_literal_overflow}}
#assert(40000'u16 == 40000's16)     // swc-expected-error {{sema_err_literal_overflow}}
#assert(200's16 == 200's8)          // swc-expected-error {{sema_err_literal_overflow}}
#assert(-1 == 0'u8)                 // swc-expected-error {{sema_err_signed_unsigned}}
