#global fileprivate

struct MissingConstUnaryMe
{
    value: s32
}

impl MissingConstUnaryMe
{
    #[Swag.Overload]
    mtd opUnary()->MissingConstUnaryMe { return {}; } // swc-expected-error {{sema_err_spec_op_signature}}
}
