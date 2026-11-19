#global private

#[Swag.TestTag("first")]
#[Swag.TestTag("second")]     // swc-expected-error {{sema_err_attribute_repeated}}
#test {}

attr SingleUse(value: s32)

#[SingleUse(1), SingleUse(2)]     // swc-expected-error {{sema_err_attribute_repeated}}
struct RepeatedAttribute {}
