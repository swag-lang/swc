#global fileprivate

#[Swag.EnumFlags]
enum MM : u32
{
    A = 5,
    B // swc-expected-error {{sema_err_flag_enum_power_2}}
}
