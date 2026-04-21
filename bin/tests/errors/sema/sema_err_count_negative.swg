#global fileprivate

#test
{
    const b = @countof(-1) // swc-expected-error {{sema_err_count_negative}}
}
