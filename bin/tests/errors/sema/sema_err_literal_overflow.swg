#global fileprivate

#print(0xFFFFFFFF_FFFFFFFF_F'u64) // swc-expected-error {{sema_err_literal_overflow}}
#print(0b11111111111111111111111111111111_111111111111111111111111111111110'u64) // swc-expected-error {{sema_err_literal_overflow}}
#print(0x1_0000_0000_0000_0000'u64) // swc-expected-error {{sema_err_literal_overflow}}
#print(0b1_00000000000000000000000000000000000000000000000000000000000000000'u64) // swc-expected-error {{sema_err_literal_overflow}}
