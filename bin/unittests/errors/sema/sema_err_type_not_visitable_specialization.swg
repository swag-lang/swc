#global private

struct MissingVisitSpecializationBox
{
    value: s32
}

#test
{
    let values = MissingVisitSpecializationBox{}
    for #Reverse value in values {} // swc-expected-error {{sema_err_type_not_visitable_specialization}}
}
