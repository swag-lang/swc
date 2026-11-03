#global if #command == Swag.CompilerCommand.Test
#global private

#test
{
    let slot = TlsAlloc()
    Swag.require(slot != TLS_OUT_OF_INDEXES)
    defer discard TlsFree(slot)
    Swag.require(TlsGetValue(slot) == null)
    var value = 42
    Swag.require(TlsSetValue(slot, &value) != 0)
    Swag.require(TlsGetValue(slot) == &value)
    Swag.require(TlsSetValue(slot, null) != 0)
    Swag.require(TlsGetValue(slot) == null)
}
