#global private

#test
{
    for index in 3 {}     // swc-expected-error {{sema_err_for_count_binding_brackets}}
}

#test
{
    for index in 1 until 3 {}     // swc-expected-error {{sema_err_for_count_binding_brackets}}
}
