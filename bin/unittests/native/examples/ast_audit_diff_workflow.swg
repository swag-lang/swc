#global fileprivate

// Real-life example: generate a strongly typed audit diff from an existing
// schema. Unlike call-site macros or mixins, #ast can materialize a brand new
// companion record with meaningful field names and matching field types.

enum RolloutMode
{
    Manual
    Progressive
    Automatic
}

struct DeployConfig
{
    replicas:      s32
    rollout:       RolloutMode
    pauseSeconds:  s32
    alertsEnabled: bool
    owner:         string
}

struct WarehouseLimits
{
    maxBins:         s32
    maxLoadKg:       s32
    requiresScan:    bool
    overflowContact: string
}

#[Swag.Compiler]
func appendAst(buffer: [*] u8, start: u64, text: string)->u64
{
    @memcpy(buffer + start, @dataof(text), @countof(text))
    return start + @countof(text)
}

#[Swag.Compiler]
func appendAuditDiffFields(buffer: [*] u8, start: u64, type: typeinfo)->u64
{
    let typeStruct = cast(const *Swag.TypeInfoStruct) type
    var len        = start

    foreach field in typeStruct.fields
    {
        len = appendAst(buffer, len, "changed_")
        len = appendAst(buffer, len, field.name)
        len = appendAst(buffer, len, ": bool\n")

        len = appendAst(buffer, len, "old_")
        len = appendAst(buffer, len, field.name)
        len = appendAst(buffer, len, ": ")
        len = appendAst(buffer, len, field.pointedType.name)
        len = appendAst(buffer, len, "\n")

        len = appendAst(buffer, len, "new_")
        len = appendAst(buffer, len, field.name)
        len = appendAst(buffer, len, ": ")
        len = appendAst(buffer, len, field.pointedType.name)
        len = appendAst(buffer, len, "\n")
    }

    return len
}

struct(T) AuditDiff
{
    #ast
    {
        var buffer: [8192] u8
        var len = appendAuditDiffFields(&buffer[0], 0, #typeof(T))
        if len == 0 do
            return ""
        return cast(string) @mkslice(&buffer[0], len)
    }
}

func(T) buildAuditDiff(before: const &T, after: const &T)->AuditDiff'T
{
    var result: AuditDiff'T
    #ast
    {
        var buffer: [8192] u8
        var len = 0'u64
        let typeStruct = cast(const *Swag.TypeInfoStruct) #typeof(T)
        foreach field in typeStruct.fields
        {
            len = appendAst(&buffer[0], len, "result.changed_")
            len = appendAst(&buffer[0], len, field.name)
            len = appendAst(&buffer[0], len, " = before.")
            len = appendAst(&buffer[0], len, field.name)
            len = appendAst(&buffer[0], len, " != after.")
            len = appendAst(&buffer[0], len, field.name)
            len = appendAst(&buffer[0], len, "\n")

            len = appendAst(&buffer[0], len, "result.old_")
            len = appendAst(&buffer[0], len, field.name)
            len = appendAst(&buffer[0], len, " = before.")
            len = appendAst(&buffer[0], len, field.name)
            len = appendAst(&buffer[0], len, "\n")

            len = appendAst(&buffer[0], len, "result.new_")
            len = appendAst(&buffer[0], len, field.name)
            len = appendAst(&buffer[0], len, " = after.")
            len = appendAst(&buffer[0], len, field.name)
            len = appendAst(&buffer[0], len, "\n")
        }
        if len == 0 do
            return ""
        return cast(string) @mkslice(&buffer[0], len)
    }
    return result
}

func(T) auditChangedCount(diff: const &AuditDiff'T)->s32
{
    var count: s32
    #ast
    {
        var buffer: [4096] u8
        var len = 0'u64
        let typeStruct = cast(const *Swag.TypeInfoStruct) #typeof(T)
        foreach field in typeStruct.fields
        {
            len = appendAst(&buffer[0], len, "if diff.changed_")
            len = appendAst(&buffer[0], len, field.name)
            len = appendAst(&buffer[0], len, " do\n")
            len = appendAst(&buffer[0], len, "    count += 1\n")
        }
        if len == 0 do
            return ""
        return cast(string) @mkslice(&buffer[0], len)
    }
    return count
}

func(T) applyAuditDiff(base: T, diff: const &AuditDiff'T)->T
{
    var result = base
    #ast
    {
        var buffer: [4096] u8
        var len = 0'u64
        let typeStruct = cast(const *Swag.TypeInfoStruct) #typeof(T)
        foreach field in typeStruct.fields
        {
            len = appendAst(&buffer[0], len, "if diff.changed_")
            len = appendAst(&buffer[0], len, field.name)
            len = appendAst(&buffer[0], len, " do\n")
            len = appendAst(&buffer[0], len, "    result.")
            len = appendAst(&buffer[0], len, field.name)
            len = appendAst(&buffer[0], len, " = diff.new_")
            len = appendAst(&buffer[0], len, field.name)
            len = appendAst(&buffer[0], len, "\n")
        }
        if len == 0 do
            return ""
        return cast(string) @mkslice(&buffer[0], len)
    }
    return result
}

#test
{
    let before: DeployConfig =
    {
        replicas: 3,
        rollout: .Manual,
        pauseSeconds: 20,
        alertsEnabled: false,
        owner: "ops@contoso.test",
    }

    let after: DeployConfig =
    {
        replicas: 6,
        rollout: .Progressive,
        pauseSeconds: 20,
        alertsEnabled: true,
        owner: "ops@contoso.test",
    }

    let diff = buildAuditDiff'(DeployConfig)(before, after)
    let rebuilt = applyAuditDiff'(DeployConfig)(before, diff)

    @assert(diff.changed_replicas)
    @assert(diff.old_replicas == 3)
    @assert(diff.new_replicas == 6)

    @assert(diff.changed_rollout)
    @assert(diff.old_rollout == .Manual)
    @assert(diff.new_rollout == .Progressive)

    @assert(!diff.changed_pauseSeconds)
    @assert(diff.old_pauseSeconds == 20)
    @assert(diff.new_pauseSeconds == 20)

    @assert(diff.changed_alertsEnabled)
    @assert(!diff.old_alertsEnabled)
    @assert(diff.new_alertsEnabled)

    @assert(!diff.changed_owner)
    @assert(diff.old_owner == "ops@contoso.test")
    @assert(diff.new_owner == "ops@contoso.test")

    @assert(auditChangedCount'(DeployConfig)(diff) == 3)
    @assert(rebuilt.replicas == 6)
    @assert(rebuilt.rollout == .Progressive)
    @assert(rebuilt.pauseSeconds == 20)
    @assert(rebuilt.alertsEnabled)
    @assert(rebuilt.owner == "ops@contoso.test")
}

#test
{
    let before: WarehouseLimits =
    {
        maxBins: 48,
        maxLoadKg: 1200,
        requiresScan: true,
        overflowContact: "night-shift@warehouse.test",
    }

    let after: WarehouseLimits =
    {
        maxBins: 48,
        maxLoadKg: 1800,
        requiresScan: false,
        overflowContact: "dispatch@warehouse.test",
    }

    let diff = buildAuditDiff'(WarehouseLimits)(before, after)
    let rebuilt = applyAuditDiff'(WarehouseLimits)(before, diff)

    @assert(!diff.changed_maxBins)
    @assert(diff.changed_maxLoadKg)
    @assert(diff.old_maxLoadKg == 1200)
    @assert(diff.new_maxLoadKg == 1800)
    @assert(diff.changed_requiresScan)
    @assert(diff.old_requiresScan)
    @assert(!diff.new_requiresScan)
    @assert(diff.changed_overflowContact)
    @assert(diff.old_overflowContact == "night-shift@warehouse.test")
    @assert(diff.new_overflowContact == "dispatch@warehouse.test")
    @assert(auditChangedCount'(WarehouseLimits)(diff) == 3)

    @assert(rebuilt.maxBins == 48)
    @assert(rebuilt.maxLoadKg == 1800)
    @assert(!rebuilt.requiresScan)
    @assert(rebuilt.overflowContact == "dispatch@warehouse.test")
}
