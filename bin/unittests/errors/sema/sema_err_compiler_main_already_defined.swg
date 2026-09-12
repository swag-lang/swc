#global private

#main
{
    fallibleMainCall()     // swc-expected-error {{sema_err_fallible_call_requires_handler}}
}

#main     // swc-expected-error {{sema_err_already_defined}}
{}

func fallibleMainCall() fail {}
