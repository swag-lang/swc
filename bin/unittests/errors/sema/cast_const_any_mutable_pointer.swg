#global private

struct CastValue { number: s32 }

#test
{
    var value: CastValue
    let readOnly: const *CastValue = &value
    let boxed: const any = readOnly
    discard catch cast(*CastValue?, boxed) // swc-expected-error {{sema_err_cannot_cast}}
}
