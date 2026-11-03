#global private

// Runtime setup must retain the TLS identity handed to dynamically loaded modules.
#test
{
    if not Swag.jit() do
        Swag.require(Swag.getContext().runtimeTlsIdPlusOne != 0)
}
