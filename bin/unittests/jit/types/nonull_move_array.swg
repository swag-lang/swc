#global private

struct JitNonNullMoveArrayDefault
{
    value: string = "reset"
}

impl JitNonNullMoveArrayDefault
{
    mtd opDrop()
    {
    }
}

struct JitNonNullMoveUndefinedEscape
{
    value: string = undefined
}

impl JitNonNullMoveUndefinedEscape
{
    mtd opDrop()
    {
    }
}

alias JitNonNullMoveArrayElementAlias = JitNonNullMoveArrayDefault
alias JitNonNullMoveArrayAlias       = [2] JitNonNullMoveArrayElementAlias
alias JitNonNullMoveArrayNestedAlias = JitNonNullMoveArrayAlias

func consumeJitNonNullMoveArray(value: JitNonNullMoveArrayNestedAlias)->bool
{
    return value[0].value == "call-a" and value[1].value == "call-b"
}

#test
{
    var source: JitNonNullMoveArrayNestedAlias = [{value: "init-a"}, {value: "init-b"}]
    let target = #move source
    @assert(target[0].value == "init-a" and target[1].value == "init-b")
    @assert(source[0].value == "reset" and source[1].value == "reset")
}

#test
{
    var source: [2] JitNonNullMoveArrayDefault = [{value: "assign-a"}, {value: "assign-b"}]
    var target: [2] JitNonNullMoveArrayDefault = [{value: "old-a"}, {value: "old-b"}]
    target = #move source
    @assert(target[0].value == "assign-a" and target[1].value == "assign-b")
    @assert(source[0].value == "reset" and source[1].value == "reset")
}

#test
{
    var source: JitNonNullMoveArrayNestedAlias = [{value: "call-a"}, {value: "call-b"}]
    @assert(consumeJitNonNullMoveArray(#move source))
    @assert(source[0].value == "reset" and source[1].value == "reset")
}

#test
{
    var source = JitNonNullMoveUndefinedEscape{value: "explicit"}
    let target = #move source
    @assert(target.value == "explicit")
}
