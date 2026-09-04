#global private

var Storage: s32

func neverStoresNull()->s32
{
    var value: *s32? = &Storage     // swc-expected-error {{sema_err_nullable_local_contract}}
    if value == null do
        return 0
    return value[]
}
