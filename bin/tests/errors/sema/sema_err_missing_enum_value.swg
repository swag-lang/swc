#global fileprivate

enum C: f32
{
    A // swc-expected-error {{sema_err_missing_enum_value}}
}
