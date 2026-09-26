#global private

#[Swag.CallingConvention(cast(Swag.CallConv) 255)] // swc-expected-error {{sema_err_calling_convention_invalid_callconv}}
func invalidDeclaredConvention() {}
