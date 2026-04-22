#global fileprivate
using Swag

public var MessageBeforeOutputValue = 0

#message(CompilerMsgMask.PassBeforeOutput)
{
    let msg = @compiler.getMessage()
    let itf = @compiler
    @assert(msg.kind == CompilerMsgKind.PassBeforeOutput)
    @assert(msg.name == "")
    @assert(msg.type == null)
    itf.compileString("#init { MessageBeforeOutputValue += 1 }\n")
}

#test
{
    if @getcontext().runtimeFlags == .FromCompiler do
        @assert(MessageBeforeOutputValue == 0)
    else do
        @assert(MessageBeforeOutputValue == 1)
}
