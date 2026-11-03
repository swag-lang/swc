#global if #command == Swag.CompilerCommand.Test
#global private

#test
{
    let success = ExportApi.depInlineNamedResult(0)
    let failure = ExportApi.depInlineNamedResult(7)
    Swag.require(success.succeeded)
    Swag.require(success.errorCode == 0)
    Swag.require(not failure.succeeded)
    Swag.require(failure.errorCode == 7)
}

#test
{
    let success = ExportApi.depNamedResult(0)
    let failure = ExportApi.depNamedResult(11)
    Swag.require(success.succeeded)
    Swag.require(success.errorCode == 0)
    Swag.require(not failure.succeeded)
    Swag.require(failure.errorCode == 11)
}

#test
{
    let result = ExportApi.depAnonymousUnionResult(42)
    Swag.require(result.bits == 42)
    Swag.require(result.signedBits == 42)
}
