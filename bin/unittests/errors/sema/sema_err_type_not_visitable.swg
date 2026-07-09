#global private

struct MissingVisitBox
{
    value: s32
}

#test
{
    let values = MissingVisitBox{}
    for value in values {} // swc-expected-error {{sema_err_type_not_visitable}}
}
