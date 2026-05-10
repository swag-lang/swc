#global fileprivate

struct MissingVisitBox
{
    value: s32
}

#test
{
    let values = MissingVisitBox{}
    foreach value in values {} // swc-expected-error {{sema_err_type_not_visitable}}
}

#test
{
    let values = MissingVisitBox{}
    foreach #reverse value in values {} // swc-expected-error {{sema_err_type_not_reverse_visitable}}
}

#test
{
    let values = MissingVisitBox{}
    foreach #Reverse value in values {} // swc-expected-error {{sema_err_type_not_visitable_specialization}}
}
