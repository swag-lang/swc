#global private

#print(0xFFFFFFFF_FFFFFFFF_F'u64)                                                     // swc-expected-error {{sema_err_literal_overflow}}
#print(0b11111111111111111111111111111111_111111111111111111111111111111110'u64)      // swc-expected-error {{sema_err_literal_overflow}}
#print(0x1_0000_0000_0000_0000'u64)                                                   // swc-expected-error {{sema_err_literal_overflow}}
#print(0b1_00000000000000000000000000000000000000000000000000000000000000000'u64)     // swc-expected-error {{sema_err_literal_overflow}}

// A named constant that does not fit is reported by its name: there is no literal at the use site.
// The wording is what is checked.
func literalOverflowNamed()->u8
{
    let wide: s32 = 300
    return wide     // swc-expected-error {{'wide' has value '300', which overflows type 'u8'}}
}

func literalOverflowLiteral()->u8 => 300     // swc-expected-error {{sema_err_literal_overflow}}
