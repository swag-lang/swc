#global private

struct AggregateCastInteger
{
    value: u16
}

func aggregateCastRejectImplicit(value: u64)
{
    let fields = AggregateCastInteger{value: value}     // swc-expected-error {{sema_err_cannot_cast}}
}
