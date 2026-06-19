#global fileprivate

// In a flag enum, a non-power-of-two explicit value prevents deducing the next flag.
#[Swag.EnumFlags]
enum A : u32
{
    A = 5,
    B                                // swc-expected-error {{sema_err_flag_enum_power_2}}
}

#[Swag.EnumFlags]
enum C : u32
{
    X = 6,
    Y                                // swc-expected-error {{sema_err_flag_enum_power_2}}
}
