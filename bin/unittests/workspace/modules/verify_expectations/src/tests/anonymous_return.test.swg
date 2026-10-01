#global if #command == Swag.CompilerCommand.Test
#global private

#test
{
    let success = ExportApi.depInlineNamedResult(0)
    let failure = ExportApi.depInlineNamedResult(7)
    Swag.assert(success.succeeded)
    Swag.assert(success.errorCode == 0)
    Swag.assert(not failure.succeeded)
    Swag.assert(failure.errorCode == 7)
}

#test
{
    let success = ExportApi.depNamedResult(0)
    let failure = ExportApi.depNamedResult(11)
    Swag.assert(success.succeeded)
    Swag.assert(success.errorCode == 0)
    Swag.assert(not failure.succeeded)
    Swag.assert(failure.errorCode == 11)
}

#test
{
    let result = ExportApi.depAnonymousUnionResult(42)
    Swag.assert(result.bits == 42)
    Swag.assert(result.signedBits == 42)
}
