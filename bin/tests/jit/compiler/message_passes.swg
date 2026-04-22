#global fileprivate
using Swag

public var MessageStageValue = 0

#message(CompilerMsgMask.PassAfterSemantic)
{
    let msg = @compiler.getMessage()
    let itf = @compiler
    @assert(msg.kind == CompilerMsgKind.PassAfterSemantic)
    @assert(msg.name == "")
    @assert(msg.type == null)
    itf.compileString("#init { MessageStageValue += 1 }\n")
}

#message(CompilerMsgMask.PassBeforeRun)
{
    let msg = @compiler.getMessage()
    let itf = @compiler
    @assert(msg.kind == CompilerMsgKind.PassBeforeRunByteCode)
    @assert(msg.name == "")
    @assert(msg.type == null)
    itf.compileString("#init { MessageStageValue += 11 }\n")
}

#test
{
    @assert(MessageStageValue == 12)
}
