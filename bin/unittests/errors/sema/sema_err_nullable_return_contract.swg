#global private

var Storage: s32

func neverReturnsNull(condition: bool)->#null *s32 // swc-expected-error {{sema_err_nullable_return_contract}}
{
    if condition do
        return &Storage
    return &Storage
}
