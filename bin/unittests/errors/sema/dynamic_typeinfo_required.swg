#global private

func uncheckedDescriptor(type: typeinfo)->const *Swag.TypeInfoStruct
{
    // swc-expected-error@(+1) {{sema_err_dynamic_cast_modifier}}
    return cast(const *Swag.TypeInfoStruct) type
}

#test
{
    // swc-expected-error@(+1) {{sema_err_cast_unrelated_structs}}
    let descriptor = cast(const *Swag.TypeInfoStruct) #typeof(42's32)
}
