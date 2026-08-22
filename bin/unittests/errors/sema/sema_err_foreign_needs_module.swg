#global private

#[Swag.Foreign]
func foreignWithoutModule()     // swc-expected-error {{sema_err_foreign_needs_module}}
