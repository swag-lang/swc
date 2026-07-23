#global private

struct NonNullRequiredFieldItem
{
    value: s32
}

struct NonNullRequiredFieldHolder
{
    required: *NonNullRequiredFieldItem
    optional: #null *NonNullRequiredFieldItem
    legacy:   *NonNullRequiredFieldItem
    count:    s32 = 7
}

struct NonNullRequiredFieldNested
{
    holder: NonNullRequiredFieldHolder
}

struct NonNullRequiredFieldBatch
{
    values: [2] NonNullRequiredFieldHolder
}

struct NonNullRequiredBlockFieldHolder
{
    required: [*] NonNullRequiredFieldItem
}

struct NonNullRequiredSliceFieldHolder
{
    required: [..] NonNullRequiredFieldItem
}

struct NonNullRequiredStringFieldHolder
{
    required: string
}

struct NonNullRequiredCStringFieldHolder
{
    required: cstring
}

struct NonNullRequiredAnyFieldHolder
{
    required: any
}

struct NonNullRequiredTypeInfoFieldHolder
{
    required: typeinfo
}

func acceptNonNullRequiredField(value: NonNullRequiredFieldHolder) {}

#test
{
    let value = NonNullRequiredFieldHolder{}     // swc-expected-error {{sema_err_struct_cast_missing_field_no_default}}
}

#test
{
    let value: NonNullRequiredFieldHolder = {count: 9}     // swc-expected-error {{sema_err_struct_cast_missing_field_no_default}}
}

#test
{
    acceptNonNullRequiredField({optional: null})     // swc-expected-error {{sema_err_struct_cast_missing_field_no_default}}
}

#test
{
    let value = NonNullRequiredFieldNested{}     // swc-expected-error {{sema_err_struct_cast_missing_field_no_default}}
}

#test
{
    let value = NonNullRequiredFieldNested{holder: {}}     // swc-expected-error {{sema_err_struct_cast_missing_field_no_default}}
}

#test
{
    let value = NonNullRequiredFieldBatch{}     // swc-expected-error {{sema_err_struct_cast_missing_field_no_default}}
}

#test
{
    let value = NonNullRequiredBlockFieldHolder{}     // swc-expected-error {{sema_err_struct_cast_missing_field_no_default}}
}

#test
{
    let value = NonNullRequiredSliceFieldHolder{}     // swc-expected-error {{sema_err_struct_cast_missing_field_no_default}}
}

#test
{
    let value = NonNullRequiredStringFieldHolder{}     // swc-expected-error {{sema_err_struct_cast_missing_field_no_default}}
}

#test
{
    let value = NonNullRequiredCStringFieldHolder{}     // swc-expected-error {{sema_err_struct_cast_missing_field_no_default}}
}

#test
{
    let value = NonNullRequiredAnyFieldHolder{}     // swc-expected-error {{sema_err_struct_cast_missing_field_no_default}}
}

#test
{
    let value = NonNullRequiredTypeInfoFieldHolder{}     // swc-expected-error {{sema_err_struct_cast_missing_field_no_default}}
}
