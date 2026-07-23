#global private

struct MissingReverseVisitBox
{
    value: s32
}

#test
{
    let values = MissingReverseVisitBox{}
    for #reverse value in values {}     // swc-expected-error {{sema_err_type_not_reverse_visitable}}
}
