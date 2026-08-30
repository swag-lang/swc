#global private
using Swag

internal var MessageBeforeOutputValue = 0

#message(CompilerMsgMask.PassBeforeOutput)
{
    let msg = Swag.compiler().getMessage()!
    let itf = Swag.compiler()
    Swag.assert(msg.kind == CompilerMsgKind.PassBeforeOutput)
    Swag.assert(msg.name == "")
    Swag.assert(msg.type == null)
    itf.compileString("#init { MessageBeforeOutputValue += 1 }\n")
}

#test
{
    if Swag.getContext().runtimeFlags == .FromCompiler do
        Swag.assert(MessageBeforeOutputValue == 0)
    else do
        Swag.assert(MessageBeforeOutputValue == 1)
}
