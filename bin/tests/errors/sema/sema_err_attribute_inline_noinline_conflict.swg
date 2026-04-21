#global fileprivate

#[Swag.Inline]
#[Swag.NoInline] // swc-expected-error {{sema_err_attribute_inline_noinline_conflict}}
func conflictInlineNoInline(a: s32, b: s32)->s32 => a + b
