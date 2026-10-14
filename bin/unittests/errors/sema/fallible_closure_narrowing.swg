#global private

// Only the safe direction converts: a callable that can fail never stands where failure is not allowed.

func runInfallible(body: func||()) { body() }

#test
{
    let failing = func() fail {}
    runInfallible(failing)     // swc-expected-error {{sema_err_cannot_cast}}
}
