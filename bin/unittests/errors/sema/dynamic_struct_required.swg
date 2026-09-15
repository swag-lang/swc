#global private

struct PlainBase { value: s32 }
struct PlainChild { using base: PlainBase; extra: s32 }

func plainDowncast(base: *PlainBase)->*PlainChild
{
    // swc-expected-error@(+1) {{sema_err_downcast_dynamic}}
    return cast(*PlainChild) base
}

#[Swag.DynCast]
struct CheckedBase { value: s32 }
struct CheckedChild { using base: CheckedBase; extra: s32 }

func uncheckedDowncast(base: *CheckedBase)->*CheckedChild
{
    // swc-expected-error@(+1) {{sema_err_dynamic_cast_modifier}}
    return cast(*CheckedChild) base
}

func checkedWithoutIdentity(base: *PlainBase)->*PlainChild?
{
    // swc-expected-error@(+1) {{sema_err_downcast_dynamic}}
    return cast #try (*PlainChild) base
}
