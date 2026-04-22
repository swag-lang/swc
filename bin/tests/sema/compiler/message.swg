#global fileprivate
using Swag

func MessageBatchEarly()->s32 => 3
public func MessageBatchLate()->s32 => 11

struct MessageLateType
{
    value: s32
}

#[Swag.Strict]
alias MessageStrictHandle = const *void

var MessageLateGlobal = 33
var MessageUnknownCountArray: [?] s32

#[Compiler]
func messageCompilerOnlyFn()
{
}

#[Compiler]
var MessageSawEarlyFunction = false

#[Compiler]
var MessageSawLateFunction = false

#[Compiler]
var MessageSawLateType = false

#[Compiler]
var MessageSawLateGlobal = false

#[Compiler]
var MessageSawStrictAlias = false

#[Compiler]
var MessageSawUnknownCountArray = false

#[Compiler]
var MessageSawCompilerOnlyFunction = false

#[Compiler]
var MessageEarlyFunctionCount = 0

#[Compiler]
var MessageLateFunctionCount = 0

#[Compiler]
var MessageLateTypeCount = 0

#[Compiler]
var MessageLateGlobalCount = 0

#[Compiler]
var MessageStrictAliasCount = 0

#[Compiler]
var MessageUnknownCountArrayCount = 0

#message(CompilerMsgMask.SemFunctions)
{
    let msg = @compiler.getMessage()
    @assert(msg.kind == CompilerMsgKind.SemFunctions)

    if msg.name == "messageCompilerOnlyFn" do
        MessageSawCompilerOnlyFunction = true

    if msg.name == "MessageBatchEarly"
    {
        MessageEarlyFunctionCount += 1
        MessageSawEarlyFunction = true
        @assert(msg.type != null)
        let itf = @compiler
        itf.compileString("const _MessageBatchedForwardRefOk = MessageBatchLate() == 11\n")
    }

    if msg.name == "MessageBatchLate"
    {
        MessageLateFunctionCount += 1
        MessageSawLateFunction = true
        let typeFunc = cast(const *TypeInfoFunc) msg.type
        @assert(@countof(typeFunc.parameters) == 0)
        @assert(typeFunc.returnType.name == "s32")
    }
}

#message(CompilerMsgMask.SemTypes)
{
    let msg = @compiler.getMessage()
    @assert(msg.kind == CompilerMsgKind.SemTypes)

    if msg.name == "MessageLateType"
    {
        MessageLateTypeCount += 1
        MessageSawLateType = true
        @assert(msg.type != null)
        @assert(msg.type.kind == TypeInfoKind.Struct)
        @assert(msg.type.name == "MessageLateType")
    }

    if msg.name == "MessageStrictHandle"
    {
        MessageStrictAliasCount += 1
        MessageSawStrictAlias = true
        @assert(msg.type != null)
        @assert(msg.type.kind == TypeInfoKind.Alias)
        @assert(msg.type.name == "MessageStrictHandle")

        let aliasType = cast(const *TypeInfoAlias) msg.type
        @assert(aliasType.rawType != null)
        @assert(aliasType.rawType.name == "const *void")
    }
}

#message(CompilerMsgMask.SemGlobals)
{
    let msg = @compiler.getMessage()
    @assert(msg.kind == CompilerMsgKind.SemGlobals)

    if msg.name == "MessageLateGlobal"
    {
        MessageLateGlobalCount += 1
        MessageSawLateGlobal = true
        @assert(msg.type != null)
        @assert(msg.type.name == "s32")
    }

    if msg.name == "MessageUnknownCountArray"
    {
        MessageUnknownCountArrayCount += 1
        MessageSawUnknownCountArray = true
        @assert(msg.type != null)
        @assert(msg.type.kind == TypeInfoKind.Array)

        let typeArray = cast(const *TypeInfoArray) msg.type
        @assert(typeArray.pointedType != null)
        @assert(typeArray.pointedType.name == "s32")
        @assert(typeArray.finalType != null)
        @assert(typeArray.finalType.name == "s32")
        @assert(typeArray.count == 0)
        @assert(typeArray.totalCount == 0)
    }
}

#message(CompilerMsgMask.PassAfterSemantic)
{
    let itf = @compiler
    @assert(MessageSawEarlyFunction)
    @assert(MessageSawLateFunction)
    @assert(MessageSawLateType)
    @assert(MessageSawLateGlobal)
    @assert(MessageSawStrictAlias)
    @assert(MessageSawUnknownCountArray)
    @assert(!MessageSawCompilerOnlyFunction)
    @assert(MessageEarlyFunctionCount == 1)
    @assert(MessageLateFunctionCount == 1)
    @assert(MessageLateTypeCount == 1)
    @assert(MessageLateGlobalCount == 1)
    @assert(MessageStrictAliasCount == 1)
    @assert(MessageUnknownCountArrayCount == 1)

    itf.compileString("#assert(_MessageBatchedForwardRefOk)\n")
}
