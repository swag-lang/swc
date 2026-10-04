#global if #command == Swag.CompilerCommand.Test
#global private

#test
{
    let slot = TlsAlloc()
    Swag.assert(slot != TLS_OUT_OF_INDEXES)
    defer discard TlsFree(slot)
    Swag.assert(TlsGetValue(slot) == null)
    var value = 42
    Swag.assert(TlsSetValue(slot, &value) != 0)
    Swag.assert(TlsGetValue(slot) == &value)
    Swag.assert(TlsSetValue(slot, null) != 0)
    Swag.assert(TlsGetValue(slot) == null)
}
