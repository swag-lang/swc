#global private

// '.count' requires a non-negative integer argument.
#test
{
    const a = (-1).count     // swc-expected-error {{sema_err_count_negative}}
}

#test
{
    const b = (-42's32).count     // swc-expected-error {{sema_err_count_negative}}
}

#test
{
    const c = (-100's64).count     // swc-expected-error {{sema_err_count_negative}}
}
