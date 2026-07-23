#global private

struct NonNullMoveArrayRequired
{
    value: string
}

impl NonNullMoveArrayRequired
{
    mtd opDrop() {}
}

alias NonNullMoveArrayElementAlias = NonNullMoveArrayRequired
alias NonNullMoveArrayAlias       = [2] NonNullMoveArrayElementAlias
alias NonNullMoveArrayNestedAlias = NonNullMoveArrayAlias

func consumeNonNullMoveArray(value: NonNullMoveArrayNestedAlias) {}

#test
{
    var source: [2] NonNullMoveArrayRequired = [{value: "a"}, {value: "b"}]
    var target: [2] NonNullMoveArrayRequired = [{value: "c"}, {value: "d"}]
    target = #move source // swc-expected-error {{sema_err_move_source_no_default}}
}

#test
{
    var source: NonNullMoveArrayNestedAlias = [{value: "a"}, {value: "b"}]
    let target = #move source // swc-expected-error {{sema_err_move_source_no_default}}
}

#test
{
    var source: NonNullMoveArrayNestedAlias = [{value: "a"}, {value: "b"}]
    consumeNonNullMoveArray(#move source) // swc-expected-error {{sema_err_move_source_no_default}}
}
