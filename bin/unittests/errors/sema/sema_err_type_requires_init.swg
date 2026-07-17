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
    var values: [2] NonNullRequiresInitForwardHolder // swc-expected-error {{sema_err_type_requires_init}}
}

struct NonNullRequiresInitForwardHolder
{
    required: #nonull *NonNullRequiresInitItem
}

struct NonNullRequiresInitHolder
{
    required: #nonull *NonNullRequiresInitItem
    count:    s32 = 7
}

struct NonNullRequiresInitNested
{
    holder: NonNullRequiresInitHolder
}

alias NonNullRequiresInitHolderAlias = NonNullRequiresInitHolder

struct NonNullRequiresInitSetTarget
{
    required: #nonull *NonNullRequiresInitItem
}

impl NonNullRequiresInitSetTarget
{
    mtd opSet(value: s32)
    {
    }
}

var NonNullRequiresInitGlobal: #nonull *NonNullRequiresInitItem // swc-expected-error {{sema_err_type_requires_init}}
var NonNullRequiresInitThrowableItem = NonNullRequiresInitItem{}

func nonNullRequiresInitRetval()->#nonull *NonNullRequiresInitItem
{
    var result: retval // swc-expected-error {{sema_err_type_requires_init}}
    return result
}

func nonNullRequiresInitThrowable()->#nonull *NonNullRequiresInitItem throw
{
    return &NonNullRequiresInitThrowableItem
}

#test
{
    let value = catch nonNullRequiresInitThrowable() // swc-expected-error {{sema_err_type_requires_init}}
}

#test
{
    let value = trycatch nonNullRequiresInitThrowable() // swc-expected-error {{sema_err_type_requires_init}}
}

#test
{
    let value = assume nonNullRequiresInitThrowable() // swc-expected-error {{sema_err_type_requires_init}}
}

#test
{
    let value = cast(NonNullRequiresInitSetTarget) 1 // swc-expected-error {{sema_err_type_requires_init}}
}

#test
{
    var value: #nonull *NonNullRequiresInitItem // swc-expected-error {{sema_err_type_requires_init}}
}

#test
{
    var value: #nonull [*] NonNullRequiresInitItem // swc-expected-error {{sema_err_type_requires_init}}
}

#test
{
    var value: #nonull [..] NonNullRequiresInitItem // swc-expected-error {{sema_err_type_requires_init}}
}

#test
{
    var value: #nonull string // swc-expected-error {{sema_err_type_requires_init}}
}

#test
{
    var value: #nonull cstring // swc-expected-error {{sema_err_type_requires_init}}
}

#test
{
    var value: #nonull any // swc-expected-error {{sema_err_type_requires_init}}
}

#test
{
    var value: #nonull typeinfo // swc-expected-error {{sema_err_type_requires_init}}
}

#test
{
    var values: [2] #nonull *NonNullRequiresInitItem // swc-expected-error {{sema_err_type_requires_init}}
}

#test
{
    var value: NonNullRequiresInitHolder // swc-expected-error {{sema_err_type_requires_init}}
}

#test
{
    var value: NonNullRequiresInitNested // swc-expected-error {{sema_err_type_requires_init}}
}

#test
{
    var value: NonNullRequiresInitHolderAlias // swc-expected-error {{sema_err_type_requires_init}}
}

#test
{
    var value: NonNullRequiresInitGenericBox'(#nonull *NonNullRequiresInitItem) // swc-expected-error {{sema_err_type_requires_init}}
}

#test
{
    var values: [2] NonNullRequiresInitHolder // swc-expected-error {{sema_err_type_requires_init}}
}

#test
{
    var item = NonNullRequiresInitItem{value: 1}
    let values: [2] NonNullRequiresInitHolder = [{required: &item}] // swc-expected-error {{sema_err_type_requires_init}}
}

#test
{
    var item = NonNullRequiresInitItem{value: 1}
    let values: [2, 2] NonNullRequiresInitHolder = [
        [{required: &item}, {required: &item}],
        [{required: &item}], // swc-expected-error {{sema_err_type_requires_init}}
    ]
}

#test
{
    var item = NonNullRequiresInitItem{value: 1}
    var ptr: #nonull *NonNullRequiresInitItem = &item
    @init(&ptr) // swc-expected-error {{sema_err_type_requires_init}}
}

#test
{
    var item = NonNullRequiresInitItem{value: 1}
    var value = NonNullRequiresInitHolder{required: &item}
    @init(value) // swc-expected-error {{sema_err_type_requires_init}}
}
