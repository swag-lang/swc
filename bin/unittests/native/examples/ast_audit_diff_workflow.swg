#global private

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
    Swag.memcpy(buffer + start, text.buffer, text.count)
    return start + text.count
}

#[Swag.Compiler]
func appendAuditDiffFields(buffer: [*] u8, start: u64, type: typeinfo)->u64
{
    let typeStruct = assume cast(const *Swag.TypeInfoStruct, type)
    var len        = start

    for field in typeStruct.fields
    {
        len = appendAst(buffer, len, "changed_")
        len = appendAst(buffer, len, unwrap field.name)
        len = appendAst(buffer, len, ": bool\n")

        len = appendAst(buffer, len, "old_")
        len = appendAst(buffer, len, field.name)
        len = appendAst(buffer, len, ": ")
        len = appendAst(buffer, len, unwrap field.pointedType!.name)
        len = appendAst(buffer, len, "\n")

        len = appendAst(buffer, len, "new_")
        len = appendAst(buffer, len, field.name)
        len = appendAst(buffer, len, ": ")
        len = appendAst(buffer, len, unwrap field.pointedType.name)
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
        return cast(string, Swag.makeSlice(&buffer[0], len))
    }
}

func(T) buildAuditDiff(before: T, after: T)->AuditDiff'T
{
    var result: AuditDiff'T
    #ast
    {
        var buffer: [8192] u8
        var len        = 0'u64
        let typeStruct = cast(const *Swag.TypeInfoStruct, #typeof(T))
        for field in typeStruct.fields
        {
            len = appendAst(&buffer[0], len, "result.changed_")
            len = appendAst(&buffer[0], len, unwrap field.name)
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
        return cast(string, Swag.makeSlice(&buffer[0], len))
    }
    return result
}

func(T) auditChangedCount(diff: AuditDiff'T)->s32
{
    var count: s32
    #ast
    {
        var buffer: [4096] u8
        var len        = 0'u64
        let typeStruct = cast(const *Swag.TypeInfoStruct, #typeof(T))
        for field in typeStruct.fields
        {
            len = appendAst(&buffer[0], len, "if diff.changed_")
            len = appendAst(&buffer[0], len, unwrap field.name)
            len = appendAst(&buffer[0], len, " do\n")
            len = appendAst(&buffer[0], len, "    count += 1\n")
        }
        if len == 0 do
            return ""
        return cast(string, Swag.makeSlice(&buffer[0], len))
    }
    return count
}

func(T) applyAuditDiff(base: T, diff: AuditDiff'T)->T
{
    var result = base
    #ast
    {
        var buffer: [4096] u8
        var len        = 0'u64
        let typeStruct = cast(const *Swag.TypeInfoStruct, #typeof(T))
        for field in typeStruct.fields
        {
            len = appendAst(&buffer[0], len, "if diff.changed_")
            len = appendAst(&buffer[0], len, unwrap field.name)
            len = appendAst(&buffer[0], len, " do\n")
            len = appendAst(&buffer[0], len, "    result.")
            len = appendAst(&buffer[0], len, field.name)
            len = appendAst(&buffer[0], len, " = diff.new_")
            len = appendAst(&buffer[0], len, field.name)
            len = appendAst(&buffer[0], len, "\n")
        }
        if len == 0 do
            return ""
        return cast(string, Swag.makeSlice(&buffer[0], len))
    }
    return result
}

#test
{
    let before: DeployConfig =
        DeployConfig{
        replicas: 3,
        rollout: .Manual,
        pauseSeconds: 20,
        alertsEnabled: false,
        owner: "ops@contoso.test"
        }

    let after: DeployConfig =
        DeployConfig{
        replicas: 6,
        rollout: .Progressive,
        pauseSeconds: 20,
        alertsEnabled: true,
        owner: "ops@contoso.test"
        }

    let diff    = buildAuditDiff'(DeployConfig)(before, after)
    let rebuilt = applyAuditDiff'(DeployConfig)(before, diff)

    Swag.require(diff.changed_replicas)
    Swag.require(diff.old_replicas == 3)
    Swag.require(diff.new_replicas == 6)

    Swag.require(diff.changed_rollout)
    Swag.require(diff.old_rollout == .Manual)
    Swag.require(diff.new_rollout == .Progressive)

    Swag.require(not diff.changed_pauseSeconds)
    Swag.require(diff.old_pauseSeconds == 20)
    Swag.require(diff.new_pauseSeconds == 20)

    Swag.require(diff.changed_alertsEnabled)
    Swag.require(not diff.old_alertsEnabled)
    Swag.require(diff.new_alertsEnabled)

    Swag.require(not diff.changed_owner)
    Swag.require(diff.old_owner == "ops@contoso.test")
    Swag.require(diff.new_owner == "ops@contoso.test")

    Swag.require(auditChangedCount'(DeployConfig)(diff) == 3)
    Swag.require(rebuilt.replicas == 6)
    Swag.require(rebuilt.rollout == .Progressive)
    Swag.require(rebuilt.pauseSeconds == 20)
    Swag.require(rebuilt.alertsEnabled)
    Swag.require(rebuilt.owner == "ops@contoso.test")
}

#test
{
    let before: WarehouseLimits =
        WarehouseLimits{
        maxBins: 48,
        maxLoadKg: 1200,
        requiresScan: true,
        overflowContact: "night-shift@warehouse.test"
        }

    let after: WarehouseLimits =
        WarehouseLimits{
        maxBins: 48,
        maxLoadKg: 1800,
        requiresScan: false,
        overflowContact: "dispatch@warehouse.test"
        }

    let diff    = buildAuditDiff'(WarehouseLimits)(before, after)
    let rebuilt = applyAuditDiff'(WarehouseLimits)(before, diff)

    Swag.require(not diff.changed_maxBins)
    Swag.require(diff.changed_maxLoadKg)
    Swag.require(diff.old_maxLoadKg == 1200)
    Swag.require(diff.new_maxLoadKg == 1800)
    Swag.require(diff.changed_requiresScan)
    Swag.require(diff.old_requiresScan)
    Swag.require(not diff.new_requiresScan)
    Swag.require(diff.changed_overflowContact)
    Swag.require(diff.old_overflowContact == "night-shift@warehouse.test")
    Swag.require(diff.new_overflowContact == "dispatch@warehouse.test")
    Swag.require(auditChangedCount'(WarehouseLimits)(diff) == 3)

    Swag.require(rebuilt.maxBins == 48)
    Swag.require(rebuilt.maxLoadKg == 1800)
    Swag.require(not rebuilt.requiresScan)
    Swag.require(rebuilt.overflowContact == "dispatch@warehouse.test")
}
