#global fileprivate

func select(value: s32)->string
{
    return "integer"
}

func(T) selectWrapped(value: T)->string
{
    return select(value) // swc-expected-error {{sema_err_cannot_cast}}
}

#run
{
    selectWrapped("hello")
}

#ast "func select(value: string)->string { return value }"
