#global private

// In a 'Swag.Propagate' body an unmarked fallible call already propagates, so a written
// 'try' changes nothing. A function declared inside that body chooses its own handling, and
// its 'try' is not redundant.

func mayFail() fail {}

#[Swag.Propagate]
func redundantTry() fail
{
    try mayFail()     // swc-expected-warning {{sema_warn_redundant_try}}
}

#[Swag.Propagate]
func redundantBlockTry() fail
{
    try     // swc-expected-warning {{sema_warn_redundant_try}}
    {
        mayFail()
    }
}

#[Swag.Propagate]
func nestedTryIsNotRedundant() fail
{
    func nested() fail
    {
        try mayFail()
    }

    nested()
}
