#global fileprivate

func select(value: s32)->string
{
    return "integer"
}

#ast "func select(value: string)->string { return value }"

func(T) selectWrapped(value: T)->string
{
    return select(value)
}

const StringSelection = #run selectWrapped("hello")
const IntSelection    = #run selectWrapped(7)

#assert(StringSelection == "hello")
#assert(IntSelection == "integer")
