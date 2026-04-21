#global fileprivate

namespace NS {}

#test
{
    NS() // swc-expected-error {{sema_err_not_callable}}
}
