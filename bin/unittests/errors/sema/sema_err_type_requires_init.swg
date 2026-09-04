#global private

struct NonNullRequiresInitItem
{
    value: s32
}

struct(T) NonNullRequiresInitGenericBox
{
    value: T
}

#test
{
    var values: [2] NonNullRequiresInitForwardHolder
    discard values     // swc-expected-error {{sema_err_definite_init_use}}
}

struct NonNullRequiresInitForwardHolder
{
    required: *NonNullRequiresInitItem
}

struct NonNullRequiresInitHolder
{
    required: *NonNullRequiresInitItem
    count:    s32 = 7
}

struct NonNullRequiresInitNested
{
    holder: NonNullRequiresInitHolder
}

alias NonNullRequiresInitHolderAlias = NonNullRequiresInitHolder

struct NonNullRequiresInitSetTarget
{
    required: *NonNullRequiresInitItem
}

impl NonNullRequiresInitSetTarget
{
    mtd opSet(value: s32) {}
}

var NonNullRequiresInitGlobal: *NonNullRequiresInitItem     // swc-expected-error {{sema_err_type_requires_init}}
var NonNullRequiresInitFallibleItem = NonNullRequiresInitItem{}

func nonNullRequiresInitRetval()->*NonNullRequiresInitItem
{
    var result: retval
    return result     // swc-expected-error {{sema_err_definite_init_use}}
}

func nonNullRequiresInitFallible()->*NonNullRequiresInitItem fail
{
    return &NonNullRequiresInitFallibleItem
}

#test
{
    let value = catch nonNullRequiresInitFallible()     // swc-expected-error {{sema_err_type_requires_init}}
}

#test
{
    let value = catch nonNullRequiresInitFallible()     // swc-expected-error {{sema_err_type_requires_init}}
}

#test
{
    let value = expect nonNullRequiresInitFallible()     // swc-expected-error {{sema_err_type_requires_init}}
}

#test
{
    let value = cast(NonNullRequiresInitSetTarget) 1     // swc-expected-error {{sema_err_type_requires_init}}
}

#test
{
    var values: [2] *NonNullRequiresInitItem
    discard values     // swc-expected-error {{sema_err_definite_init_use}}
}

#test
{
    var values: [2] NonNullRequiresInitHolder
    discard values     // swc-expected-error {{sema_err_definite_init_use}}
}

#test
{
    var item = NonNullRequiresInitItem{value: 1}
    let values: [2] NonNullRequiresInitHolder = [{required: &item}]     // swc-expected-error {{sema_err_type_requires_init}}
}

#test
{
    var item = NonNullRequiresInitItem{value: 1}
    let values: [2, 2] NonNullRequiresInitHolder = [
        [{required: &item}, {required: &item}],
        [{required: &item}]     // swc-expected-error {{sema_err_type_requires_init}}
        ]
}

#test
{
    var item = NonNullRequiresInitItem{value: 1}
    var ptr: *NonNullRequiresInitItem = &item
    Swag.init(&ptr)     // swc-expected-error {{sema_err_type_requires_init}}
}

#test
{
    var item  = NonNullRequiresInitItem{value: 1}
    var value = NonNullRequiresInitHolder{required: &item}
    Swag.init(value)     // swc-expected-error {{sema_err_type_requires_init}}
}

// The diagnostic must point at the declaration itself, even when the check has to
// wait for the completion of a struct declared later in the file.
var NonNullLateGlobal: *NonNullLateStruct     // swc-expected-error {{sema_err_type_requires_init}}

struct NonNullLateStruct
{
    required: *NonNullRequiresInitItem
}
