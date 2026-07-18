#global private
#global #[Swag.ExplicitNullability]

struct SemaNonNullMoveArrayDefault
{
    value: #nonull string = "reset"
}

impl SemaNonNullMoveArrayDefault
{
    mtd opDrop()
    {
    }
}

struct SemaNonNullMoveUndefinedEscape
{
    value: #nonull string = undefined
}

impl SemaNonNullMoveUndefinedEscape
{
    mtd opDrop()
    {
    }
}

alias SemaNonNullMoveArrayElementAlias = SemaNonNullMoveArrayDefault
alias SemaNonNullMoveArrayAlias       = [2] SemaNonNullMoveArrayElementAlias
alias SemaNonNullMoveArrayNestedAlias = SemaNonNullMoveArrayAlias

func consumeSemaNonNullMoveArray(value: SemaNonNullMoveArrayNestedAlias)->bool
{
    return value[0].value == "call-a" and value[1].value == "call-b"
}

func semaNonNullMoveArrayDefaults()
{
    var initSource: SemaNonNullMoveArrayNestedAlias = [{value: "init-a"}, {value: "init-b"}]
    let initTarget = #move initSource

    var assignSource: [2] SemaNonNullMoveArrayDefault = [{value: "assign-a"}, {value: "assign-b"}]
    var assignTarget: [2] SemaNonNullMoveArrayDefault = [{value: "old-a"}, {value: "old-b"}]
    assignTarget = #move assignSource

    var callSource: SemaNonNullMoveArrayNestedAlias = [{value: "call-a"}, {value: "call-b"}]
    let callResult = consumeSemaNonNullMoveArray(#move callSource)

    var escapeSource = SemaNonNullMoveUndefinedEscape{value: "explicit"}
    let escapeTarget = #move escapeSource

    #assert(#typeof(initTarget) == [2] SemaNonNullMoveArrayDefault)
    #assert(#typeof(assignTarget) == [2] SemaNonNullMoveArrayDefault)
    #assert(#typeof(callResult) == bool)
    #assert(#typeof(escapeTarget.value) == #nonull string)
}
