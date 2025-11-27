#assert(12's8 == 12's8)
#assert(12's16 == 12's16)
#assert(12's32 == 12's32)
#assert(12's64 == 12's64)
#assert(12'u8 == 12'u8)
#assert(12'u16 == 12'u16)
#assert(12'u32 == 12'u32)
#assert(12'u64 == 12'u64)

#assert(1244's8 == 0) // swc-expected-error {{sema_err_literal_overflow}}

// --- signed 8-bit limits ---
#assert(127's8  == 127's8)
//#assert(-128's8 == -128's8)
#assert(128's8  == 0's8)   // swc-expected-error {{sema_err_literal_overflow}}
//#assert(-129's8 == 0's8)   // swc-expected-error {{sema_err_literal_overflow}}

// --- unsigned 8-bit limits ---
#assert(255'u8 == 255'u8)
#assert(256'u8 == 0'u8)    // swc-expected-error {{sema_err_literal_overflow}}

// --- signed 16-bit limits ---
#assert(32767's16  == 32767's16)
//#assert(-32768's16 == -32768's16)
#assert(32768's16  == 0's16)    // swc-expected-error {{sema_err_literal_overflow}}
//#assert(-32769's16 == 0)    // swc-expected-error {{sema_err_literal_overflow}}

// --- unsigned 16-bit limits ---
#assert(65535'u16 == 65535'u16)
#assert(65536'u16 == 0'u16)     // swc-expected-error {{sema_err_literal_overflow}}

// --- large unsigned 32-bit boundary ---
#assert(4294967295'u32 == 4294967295'u32)  // 2^32 - 1
#assert(4294967296'u32 == 0'u32)              // swc-expected-error {{sema_err_literal_overflow}}$

#print(1.0's32)