#global if #command == Swag.CompilerCommand.Test

#test
{
    let result = RuntimeCtxBridge.ctxSharedCheckedResult()
    let failed = Swag.g_TestFailed
    Swag.g_TestFailed = false
    Swag.require(result == 42 and failed)
}
