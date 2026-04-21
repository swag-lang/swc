#global fileprivate

namespace NS {}
struct S {}

// Calling something that is not a function or lambda is reported.
#test
{
    NS()                             // swc-expected-error {{sema_err_not_callable}}
}

#test
{
    S()                              // swc-expected-error {{sema_err_not_callable}}
}

#test
{
    var a = 42
    a()                              // swc-expected-error {{sema_err_not_callable}}
}
