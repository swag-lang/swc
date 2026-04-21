#global fileprivate

// '@countof' requires a non-negative integer argument.
#test
{
    const a = @countof(-1)                   // swc-expected-error {{sema_err_count_negative}}
}

#test
{
    const b = @countof(-42's32)              // swc-expected-error {{sema_err_count_negative}}
}

#test
{
    const c = @countof(-100's64)             // swc-expected-error {{sema_err_count_negative}}
}
