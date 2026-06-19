#global fileprivate

#[Swag.Inline]
#[Swag.Macro] // swc-expected-error {{sema_err_attribute_inline_macro_mixin_conflict}}
func conflictInlineMacro(a: s32)->s32 => a

#[Swag.Mixin]
#[Swag.Inline] // swc-expected-error {{sema_err_attribute_inline_macro_mixin_conflict}}
func conflictMixinInline(a: s32)->s32 => a

#[Swag.Macro]
#[Swag.Mixin] // swc-expected-error {{sema_err_attribute_inline_macro_mixin_conflict}}
func conflictMacroMixin(a: s32)->s32 => a
