// An invalid injected unary expression reports its diagnostic through the generated-source
// provenance chain instead of combining spans from two source views.

struct Values
{
    value: s32
}

impl Values
{
    #[Macro]
    mtd(ptr: bool) opVisit(stmt: #code(item))
    {
        #inject(stmt, item = dref cast(&s32) &.value)     // swc-expected-error {{sema_err_unary_operand_type}}
    }
}

#test
{
    var values: Values
    for item in values do     // swc-expected-note {{sema_note_expansion_invoked_here}}
        discard item
}
