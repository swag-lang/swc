#global private

struct NativeNonNullMoveArrayDefault
{
    value: string = "reset"
}

impl NativeNonNullMoveArrayDefault
{
    mtd opDrop()
    {
    }
}

struct NativeNonNullMoveUndefinedEscape
{
    value: string = undefined
}

impl NativeNonNullMoveUndefinedEscape
{
    mtd opDrop()
    {
    }
}

alias NativeNonNullMoveArrayElementAlias = NativeNonNullMoveArrayDefault
alias NativeNonNullMoveArrayAlias       = [2] NativeNonNullMoveArrayElementAlias
alias NativeNonNullMoveArrayNestedAlias = NativeNonNullMoveArrayAlias

func consumeNativeNonNullMoveArray(value: NativeNonNullMoveArrayNestedAlias)->bool
{
    return value[0].value == "call-a" and value[1].value == "call-b"
}

#test
{
    var source: NativeNonNullMoveArrayNestedAlias = [{value: "init-a"}, {value: "init-b"}]
    let target = #move source
    @assert(target[0].value == "init-a" and target[1].value == "init-b")
    @assert(source[0].value == "reset" and source[1].value == "reset")
}

#test
{
    var source: [2] NativeNonNullMoveArrayDefault = [{value: "assign-a"}, {value: "assign-b"}]
    var target: [2] NativeNonNullMoveArrayDefault = [{value: "old-a"}, {value: "old-b"}]
    target = #move source
    @assert(target[0].value == "assign-a" and target[1].value == "assign-b")
    @assert(source[0].value == "reset" and source[1].value == "reset")
}

#test
{
    var source: NativeNonNullMoveArrayNestedAlias = [{value: "call-a"}, {value: "call-b"}]
    @assert(consumeNativeNonNullMoveArray(#move source))
    @assert(source[0].value == "reset" and source[1].value == "reset")
}

#test
{
    var source = NativeNonNullMoveUndefinedEscape{value: "explicit"}
    let target = #move source
    @assert(target.value == "explicit")
}
