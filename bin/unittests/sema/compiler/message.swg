#global private
using Swag

#[AttrUsage(AttributeUsage.Function)]
attr MessageMarker()

func MessageBatchEarly()->s32       => 3
public func MessageBatchLate()->s32 => 11
func MessagePlaceholderOnly(value: s32)->s32

#[MessageMarker]
func MessageMarkedNoParam()->u32 => 1

func MessagePlainNoParam()->u32 => 2

struct MessageLateType
{
    value: s32
}

#[Swag.Strict]
alias MessageStrictHandle = const *void

var MessageLateGlobal = 33
var MessageUnknownCountArray: [?] s32

#[Compiler]
func messageCompilerOnlyFn() {}

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
var MessageSawPlaceholderFunction = false

#[Compiler]
var MessageSawMarkedNoParam = false

#[Compiler]
var MessageSawPlainNoParam = false

#[Compiler]
var MessageEarlyFunctionCount = 0

#[Compiler]
var MessageLateFunctionCount = 0

#[Compiler]
var MessagePlaceholderFunctionCount = 0

#[Compiler]
var MessageMarkedNoParamCount = 0

#[Compiler]
var MessagePlainNoParamCount = 0

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
    let msg = Swag.compiler().getMessage()!
    Swag.assert(msg.kind == CompilerMsgKind.SemFunctions)

    if msg.name == "messageCompilerOnlyFn" do
        MessageSawCompilerOnlyFunction = true

    if msg.name == "MessageBatchEarly"
    {
        MessageEarlyFunctionCount += 1
        MessageSawEarlyFunction   = true
        Swag.assert(msg.type != null)
        let itf = Swag.compiler()
        itf.compileString("const _MessageBatchedForwardRefOk = MessageBatchLate() == 11\n")
    }

    if msg.name == "MessageBatchLate"
    {
        MessageLateFunctionCount += 1
        MessageSawLateFunction   = true
        let typeFunc = cast(const *TypeInfoFunc) msg.type!
        Swag.assert(typeFunc.parameters.count == 0)
        Swag.assert(typeFunc.returnType!.name == "s32")
    }

    if msg.name == "MessagePlaceholderOnly"
    {
        MessagePlaceholderFunctionCount += 1
        MessageSawPlaceholderFunction   = true
        let typeFunc = cast(const *TypeInfoFunc) msg.type!
        let params   = typeFunc.parameters!
        Swag.assert(params.count == 1)
        Swag.assert(params[0].name == "value")
        Swag.assert(params[0].pointedType!.name == "s32")
        Swag.assert(typeFunc.returnType!.name == "s32")
    }

    if msg.name == "MessageMarkedNoParam"
    {
        MessageMarkedNoParamCount += 1
        MessageSawMarkedNoParam   = true
        let typeFunc = cast(const *TypeInfoFunc) msg.type!
        Swag.assert(typeFunc.parameters.count == 0)
        Swag.assert(typeFunc.returnType!.name == "u32")
        var foundMarker = false
        for attribute in typeFunc.attributes where attribute.type == #typeof(MessageMarker) do
            foundMarker = true
        Swag.assert(foundMarker)
    }

    if msg.name == "MessagePlainNoParam"
    {
        MessagePlainNoParamCount += 1
        MessageSawPlainNoParam   = true
        let typeFunc = cast(const *TypeInfoFunc) msg.type!
        Swag.assert(typeFunc.parameters.count == 0)
        Swag.assert(typeFunc.returnType!.name == "u32")
        for attribute in typeFunc.attributes do
            Swag.assert(attribute.type != #typeof(MessageMarker))
    }
}

#message(CompilerMsgMask.SemTypes)
{
    let msg = Swag.compiler().getMessage()!
    Swag.assert(msg.kind == CompilerMsgKind.SemTypes)

    if msg.name == "MessageLateType"
    {
        MessageLateTypeCount += 1
        MessageSawLateType   = true
        let msgType = msg.type!
        Swag.assert(msgType.kind == TypeInfoKind.Struct)
        Swag.assert(msgType.name == "MessageLateType")
    }

    if msg.name == "MessageStrictHandle"
    {
        MessageStrictAliasCount += 1
        MessageSawStrictAlias   = true
        let msgType = msg.type!
        Swag.assert(msgType.kind == TypeInfoKind.Alias)
        Swag.assert(msgType.name == "MessageStrictHandle")

        let aliasType = cast(const *TypeInfoAlias) msgType
        let rawType   = aliasType.rawType!
        Swag.assert(rawType.name == "const *void")
    }
}

#message(CompilerMsgMask.SemGlobals)
{
    let msg = Swag.compiler().getMessage()!
    Swag.assert(msg.kind == CompilerMsgKind.SemGlobals)

    if msg.name == "MessageLateGlobal"
    {
        MessageLateGlobalCount += 1
        MessageSawLateGlobal   = true
        Swag.assert(msg.type!.name == "s32")
    }

    if msg.name == "MessageUnknownCountArray"
    {
        MessageUnknownCountArrayCount += 1
        MessageSawUnknownCountArray   = true
        let msgType = msg.type!
        Swag.assert(msgType.kind == TypeInfoKind.Array)

        let typeArray = cast(const *TypeInfoArray) msgType
        Swag.assert(typeArray.pointedType!.name == "s32")
        Swag.assert(typeArray.finalType!.name == "s32")
        Swag.assert(typeArray.count == 0)
        Swag.assert(typeArray.totalCount == 0)
    }
}

#message(CompilerMsgMask.PassAfterSemantic)
{
    let itf = Swag.compiler()
    Swag.assert(MessageSawEarlyFunction)
    Swag.assert(MessageSawLateFunction)
    Swag.assert(MessageSawPlaceholderFunction)
    Swag.assert(MessageSawMarkedNoParam)
    Swag.assert(MessageSawPlainNoParam)
    Swag.assert(MessageSawLateType)
    Swag.assert(MessageSawLateGlobal)
    Swag.assert(MessageSawStrictAlias)
    Swag.assert(MessageSawUnknownCountArray)
    Swag.assert(!MessageSawCompilerOnlyFunction)
    Swag.assert(MessageEarlyFunctionCount == 1)
    Swag.assert(MessageLateFunctionCount == 1)
    Swag.assert(MessagePlaceholderFunctionCount == 1)
    Swag.assert(MessageMarkedNoParamCount == 1)
    Swag.assert(MessagePlainNoParamCount == 1)
    Swag.assert(MessageLateTypeCount == 1)
    Swag.assert(MessageLateGlobalCount == 1)
    Swag.assert(MessageStrictAliasCount == 1)
    Swag.assert(MessageUnknownCountArrayCount == 1)

    itf.compileString("#assert(_MessageBatchedForwardRefOk)\n")
}
