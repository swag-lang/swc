#global private
using Swag

internal var MessageStageValue = 0

#message(CompilerMsgMask.PassAfterSemantic)
{
    let msg = Swag.compiler().getMessage()!
    let itf = Swag.compiler()
    Swag.assert(msg.kind == CompilerMsgKind.PassAfterSemantic)
    Swag.assert(msg.name == "")
    Swag.assert(msg.type == null)
    itf.compileString("#init { MessageStageValue += 1 }\n")
}

#message(CompilerMsgMask.PassBeforeRun)
{
    let msg = Swag.compiler().getMessage()!
    let itf = Swag.compiler()
    Swag.assert(msg.kind == CompilerMsgKind.PassBeforeRunByteCode)
    Swag.assert(msg.name == "")
    Swag.assert(msg.type == null)
    itf.compileString("#init { MessageStageValue += 11 }\n")
}

#test
{
    Swag.assert(MessageStageValue == 12)
}
