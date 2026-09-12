#global private

struct AggregateCastPointer
{
    pointer: *void
}

struct AggregateCastInteger
{
    value: u16
}

func aggregateCastRejectImplicit(value: u64)
{
    let fields = AggregateCastInteger{value: value}     // swc-expected-error {{sema_err_cannot_cast}}
}

func aggregateCastRejectDeducedAddress(value: u32)
{
    let fields = AggregateCastPointer{pointer: cast() value}     // swc-expected-error {{sema_err_cannot_cast}}
}

func aggregateCastRejectDeducedArrayAddress(value: u32)
{
    let pointers: [1] *void = [cast() value]     // swc-expected-error {{sema_err_cannot_cast}}
}
