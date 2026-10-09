#global private

// A generic struct is a family of types. A value needs one of its specializations, and a
// specialization written in the source names what it lacks or what it has too many of.

struct(var T) GenericFamilyBox
{
    value: T
}

struct(var T, var U) GenericFamilyPair
{
    first:  T
    second: U
}

struct(var T = s32) GenericFamilyDefault
{
    value: T
}

struct GenericFamilyHolder
{
    box: GenericFamilyBox     // swc-expected-error {{sema_err_generic_struct_needs_args}}
}

func genericFamilyBare()
{
    var box: GenericFamilyBox     // swc-expected-error {{sema_err_generic_struct_needs_args}}
    discard box
}

func genericFamilyMissing()
{
    var pair: GenericFamilyPair'(s32)     // swc-expected-error {{sema_err_generic_struct_missing_arg}}
    discard pair
}

func genericFamilyTooMany()
{
    var box: GenericFamilyBox'(s32, bool)     // swc-expected-error {{sema_err_generic_struct_too_many_args}}
    discard box
}

func genericFamilyDefault()->s32
{
    var value: GenericFamilyDefault
    value.value = 3
    return value.value
}
