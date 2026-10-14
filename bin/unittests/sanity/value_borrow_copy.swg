#global private

#[Swag.NoCopy]
struct Unique { first, second, third: u64 }
func cannotCopy(value: Unique)
{
    discard #copy value     // swc-expected-error {{sema_err_cannot_copy_nocopy}}
}
func cannotCopyFresh()
{
    discard #copy Unique{}     // swc-expected-error {{sema_err_cannot_copy_nocopy}}
}

struct InlineData { values: [3] u64 }
func escapingCopy(value: *InlineData)->const [..] u64
{
    return (#copy value[]).values     // swc-expected-error {{sanity_err_borrow_temporary}}
}
