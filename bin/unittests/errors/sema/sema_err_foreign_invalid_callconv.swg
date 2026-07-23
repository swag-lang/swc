#global private

#[Swag.Foreign("system", callconv: cast(Swag.CallConv) 255)]     // swc-expected-error {{sema_err_foreign_invalid_callconv}}
func invalidForeignConvention();
