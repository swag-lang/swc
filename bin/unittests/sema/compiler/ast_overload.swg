#global fileprivate

func select(value: s32)->string
{
    return "integer"
}

#ast "func select(value: string)->string { return value }"
#ast "func select(value: bool)->string { return value ? \"true\" : \"false\" }"

func(T) selectWrapped(value: T)->string
{
    return select(value)
}

const StringSelection = #run selectWrapped("hello")
const BoolSelection   = #run selectWrapped(true)
const IntSelection    = #run selectWrapped(7)

#assert(StringSelection == "hello")
#assert(BoolSelection == "true")
#assert(IntSelection == "integer")
