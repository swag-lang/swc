#global fileprivate

namespace NS {}

#test
{
    const x = #alignof(NS) // swc-expected-error {{sema_err_invalid_alignof}}
}
