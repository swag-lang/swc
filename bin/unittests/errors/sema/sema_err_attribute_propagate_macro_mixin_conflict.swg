#global private

// A macro or a mixin body expands into its caller and follows the caller's error handling,
// so it cannot choose implicit propagation for itself.

#[Swag.Macro]
#[Swag.Propagate]     // swc-expected-error {{sema_err_attribute_propagate_macro_mixin_conflict}}
func propagateMacro() fail {}

#[Swag.Propagate]
#[Swag.Mixin]     // swc-expected-error {{sema_err_attribute_propagate_macro_mixin_conflict}}
func propagateMixin() fail {}
