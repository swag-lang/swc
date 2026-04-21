#global fileprivate

// Real-life example: compile ordinary service handlers into a typed command
// layer. One #ast pass generates named request records, validators, redactors,
// secret counters, and dispatch shims from function signatures plus custom
// attributes. That is much closer to a small source generator than to classic
// templates.

using Swag

attr IntRangeRule(param: string, min: s32, max: s32)
attr StringPolicyRule(param: string, minChars: s32, nonEmpty: bool = false, secret: bool = false)

enum DeploymentDecision
{
    Accepted
    DryRunOnly
    Rejected
}

struct WireReceipt
{
    approved:       bool
    queueSlot:      s32
    reviewRequired: bool
}

#[IntRangeRule("replicas", 1, 24)]
#[StringPolicyRule("region", 3, true)]
#[StringPolicyRule("authToken", 16, false, true)]
func scheduleDeployment(replicas: s32, region: string, dryRun: bool, authToken: string)->DeploymentDecision
{
    if dryRun do
        return .DryRunOnly
    if replicas > 12 do
        return .Rejected
    if region == "legacy-eu" do
        return .Rejected
    if @countof(authToken) < 16 do
        return .Rejected
    return .Accepted
}

#[IntRangeRule("cents", 100, 1_000_000)]
#[StringPolicyRule("toAccount", 4, true)]
#[StringPolicyRule("approvalCode", 6, false, true)]
func submitWireTransfer(cents: s32, toAccount: string, approvalCode: string)->WireReceipt
{
    let approved = cents <= 500_000 and @countof(approvalCode) >= 6
    let queueSlot = cents / 100
    return {approved: approved, queueSlot: queueSlot, reviewRequired: cents > 200_000}
}

func resyncCatalog()->bool => true

#[Swag.Compiler]
func appendAst(buffer: [*] u8, start: u64, text: string)->u64
{
    @memcpy(buffer + start, @dataof(text), @countof(text))
    return start + @countof(text)
}

#[Swag.Compiler]
func appendS32Literal(buffer: [*] u8, start: u64, value: s32)->u64
{
    var len = start
    var v   = cast(s64) value

    if v < 0
    {
        buffer[len] = '-'
        len += 1
        v = -v
    }

    if v == 0
    {
        buffer[len] = '0'
        return len + 1
    }

    var tmp: [24] u8
    var tmpLen: u64
    while true
    {
        if v == 0 do
            break
        tmp[tmpLen] = cast(u8) (v % 10) + '0'
        tmpLen += 1
        v /= 10
    }

    for #reverse i in tmpLen
    {
        buffer[len] = tmp[i]
        len += 1
    }

    return len
}

#[Swag.Compiler]
func appendCommandEnvelopeDefinition(buffer: [*] u8, start: u64, contractName: string, type: typeinfo)->u64
{
    let typeFunc = cast(const *Swag.TypeInfoFunc) type
    var len      = start

    len = appendAst(buffer, len, "struct ")
    len = appendAst(buffer, len, contractName)
    len = appendAst(buffer, len, "\n{\n")

    foreach parameter in typeFunc.parameters
    {
        len = appendAst(buffer, len, "    ")
        len = appendAst(buffer, len, parameter.name)
        len = appendAst(buffer, len, ": ")
        len = appendAst(buffer, len, parameter.pointedType.name)
        len = appendAst(buffer, len, "\n")
    }

    len = appendAst(buffer, len, "}\n\n")
    return len
}

#[Swag.Compiler]
func appendCommandValidation(buffer: [*] u8, start: u64, contractName: string, type: typeinfo)->u64
{
    let typeFunc = cast(const *Swag.TypeInfoFunc) type
    var len      = start

    len = appendAst(buffer, len, "func validate")
    len = appendAst(buffer, len, contractName)
    len = appendAst(buffer, len, "(command: const &")
    len = appendAst(buffer, len, contractName)
    len = appendAst(buffer, len, ")->bool\n{\n")
    len = appendAst(buffer, len, "    var ok = true\n")

    foreach parameter in typeFunc.parameters
    {
        foreach attribute in typeFunc.attributes
        {
            if cast(string) attribute.params[0].value != parameter.name do
                continue

            if attribute.type == #typeof(IntRangeRule)
            {
                len = appendAst(buffer, len, "    ok = ok and command.")
                len = appendAst(buffer, len, parameter.name)
                len = appendAst(buffer, len, " >= ")
                len = appendS32Literal(buffer, len, cast(s32) attribute.params[1].value)
                len = appendAst(buffer, len, " and command.")
                len = appendAst(buffer, len, parameter.name)
                len = appendAst(buffer, len, " <= ")
                len = appendS32Literal(buffer, len, cast(s32) attribute.params[2].value)
                len = appendAst(buffer, len, "\n")
                continue
            }

            if attribute.type == #typeof(StringPolicyRule)
            {
                if cast(bool) attribute.params[2].value
                {
                    len = appendAst(buffer, len, "    ok = ok and @countof(command.")
                    len = appendAst(buffer, len, parameter.name)
                    len = appendAst(buffer, len, ") > 0\n")
                }

                len = appendAst(buffer, len, "    ok = ok and @countof(command.")
                len = appendAst(buffer, len, parameter.name)
                len = appendAst(buffer, len, ") >= ")
                len = appendS32Literal(buffer, len, cast(s32) attribute.params[1].value)
                len = appendAst(buffer, len, "\n")
            }
        }
    }

    len = appendAst(buffer, len, "    return ok\n}\n\n")
    return len
}

#[Swag.Compiler]
func appendCommandRedaction(buffer: [*] u8, start: u64, contractName: string, type: typeinfo)->u64
{
    let typeFunc = cast(const *Swag.TypeInfoFunc) type
    var len      = start

    len = appendAst(buffer, len, "func redact")
    len = appendAst(buffer, len, contractName)
    len = appendAst(buffer, len, "(command: const &")
    len = appendAst(buffer, len, contractName)
    len = appendAst(buffer, len, ")->")
    len = appendAst(buffer, len, contractName)
    len = appendAst(buffer, len, "\n{\n")
    len = appendAst(buffer, len, "    var result = cast(")
    len = appendAst(buffer, len, contractName)
    len = appendAst(buffer, len, ") command\n")

    foreach parameter in typeFunc.parameters
    {
        foreach attribute in typeFunc.attributes
        {
            if cast(string) attribute.params[0].value != parameter.name do
                continue
            if attribute.type != #typeof(StringPolicyRule) do
                continue
            if !cast(bool) attribute.params[3].value do
                continue

            len = appendAst(buffer, len, "    result.")
            len = appendAst(buffer, len, parameter.name)
            len = appendAst(buffer, len, " = \"<redacted>\"\n")
        }
    }

    len = appendAst(buffer, len, "    return result\n}\n\n")
    return len
}

#[Swag.Compiler]
func appendCommandSecretCount(buffer: [*] u8, start: u64, contractName: string, type: typeinfo)->u64
{
    let typeFunc = cast(const *Swag.TypeInfoFunc) type
    var len      = start

    len = appendAst(buffer, len, "func count")
    len = appendAst(buffer, len, contractName)
    len = appendAst(buffer, len, "Secrets()->s32\n{\n")
    len = appendAst(buffer, len, "    var count: s32\n")

    foreach parameter in typeFunc.parameters
    {
        foreach attribute in typeFunc.attributes
        {
            if cast(string) attribute.params[0].value != parameter.name do
                continue
            if attribute.type != #typeof(StringPolicyRule) do
                continue
            if !cast(bool) attribute.params[3].value do
                continue

            len = appendAst(buffer, len, "    count += 1\n")
        }
    }

    len = appendAst(buffer, len, "    return count\n}\n\n")
    return len
}

#[Swag.Compiler]
func appendCommandInvoke(buffer: [*] u8, start: u64, contractName, handlerName: string, type: typeinfo)->u64
{
    let typeFunc    = cast(const *Swag.TypeInfoFunc) type
    let returnsVoid = typeFunc.returnType == null or typeFunc.returnType == void
    var len         = start

    len = appendAst(buffer, len, "func invoke")
    len = appendAst(buffer, len, contractName)
    len = appendAst(buffer, len, "(command: const &")
    len = appendAst(buffer, len, contractName)
    len = appendAst(buffer, len, ")")
    if !returnsVoid
    {
        len = appendAst(buffer, len, "->")
        len = appendAst(buffer, len, typeFunc.returnType.name)
    }

    len = appendAst(buffer, len, "\n{\n    ")
    if !returnsVoid do
        len = appendAst(buffer, len, "return ")
    len = appendAst(buffer, len, handlerName)
    len = appendAst(buffer, len, "(")

    foreach parameter, index in typeFunc.parameters
    {
        if index != 0 do
            len = appendAst(buffer, len, ", ")

        len = appendAst(buffer, len, "command.")
        len = appendAst(buffer, len, parameter.name)
    }

    len = appendAst(buffer, len, ")\n}\n\n")
    return len
}

#[Swag.Compiler]
func appendCommandContract(buffer: [*] u8, start: u64, contractName, handlerName: string, type: typeinfo)->u64
{
    var len = start
    len = appendCommandEnvelopeDefinition(buffer, len, contractName, type)
    len = appendCommandValidation(buffer, len, contractName, type)
    len = appendCommandRedaction(buffer, len, contractName, type)
    len = appendCommandSecretCount(buffer, len, contractName, type)
    len = appendCommandInvoke(buffer, len, contractName, handlerName, type)
    return len
}

#ast
{
    var buffer: [32768] u8
    var len = 0'u64

    len = appendCommandContract(&buffer[0], len, "ScheduleDeploymentCommand", "scheduleDeployment", #typeof(scheduleDeployment))
    len = appendCommandContract(&buffer[0], len, "SubmitWireTransferCommand", "submitWireTransfer", #typeof(submitWireTransfer))
    len = appendCommandContract(&buffer[0], len, "ResyncCatalogCommand", "resyncCatalog", #typeof(resyncCatalog))

    if len == 0 do
        return ""
    return cast(string) @mkslice(&buffer[0], len)
}

#test
{
    var command: ScheduleDeploymentCommand
    command.replicas = 6
    command.region = "eu-west"
    command.dryRun = false
    command.authToken = "tok_0123456789abcd"

    let redacted = redactScheduleDeploymentCommand(command)
    let result = invokeScheduleDeploymentCommand(command)

    @assert(command.replicas == 6)
    @assert(command.region == "eu-west")
    @assert(@countof(command.region) == 7)
    @assert(@countof(command.authToken) >= 16)
    @assert(validateScheduleDeploymentCommand(command))
    @assert(countScheduleDeploymentCommandSecrets() == 1)
    @assert(redacted.replicas == 6)
    @assert(redacted.region == "eu-west")
    @assert(!redacted.dryRun)
    @assert(redacted.authToken == "<redacted>")
    @assert(result == .Accepted)
}

#test
{
    var command: ScheduleDeploymentCommand
    command.replicas = 30
    command.region = "eu"
    command.dryRun = false
    command.authToken = "short"

    let redacted = redactScheduleDeploymentCommand(command)

    @assert(!validateScheduleDeploymentCommand(command))
    @assert(redacted.authToken == "<redacted>")
}

#test
{
    var command: SubmitWireTransferCommand
    command.cents = 250_000
    command.toAccount = "acct-7781"
    command.approvalCode = "APR-8832"

    let receipt = invokeSubmitWireTransferCommand(command)
    let redacted = redactSubmitWireTransferCommand(command)

    @assert(validateSubmitWireTransferCommand(command))
    @assert(countSubmitWireTransferCommandSecrets() == 1)
    @assert(receipt.approved)
    @assert(receipt.queueSlot == 2500)
    @assert(receipt.reviewRequired)
    @assert(redacted.cents == 250_000)
    @assert(redacted.toAccount == "acct-7781")
    @assert(redacted.approvalCode == "<redacted>")
}

#test
{
    let command: ResyncCatalogCommand = {}

    @assert(validateResyncCatalogCommand(command))
    @assert(countResyncCatalogCommandSecrets() == 0)
    @assert(invokeResyncCatalogCommand(command))
}
