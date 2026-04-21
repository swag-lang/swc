#global fileprivate

// Real-life example: generate API PATCH payloads from settings structs. The
// compile-time code emits per-field change flags, payload storage, merge
// helpers, and stable change masks from one source schema.

enum PlanTier
{
    Starter
    Growth
    Enterprise
}

struct TenantSettings
{
    seatLimit:          s32
    storageGb:          s32
    auditRetentionDays: s32
    ssoEnabled:         bool
    billingEmail:       string
    tier:               PlanTier
}

struct NotificationPolicy
{
    dailyDigest:       bool
    weeklyReport:      bool
    escalationMinutes: s32
    smsEnabled:        bool
}

#[Swag.Compiler]
func appendAst(buffer: [*] u8, start: u64, text: string)->u64
{
    @memcpy(buffer + start, @dataof(text), @countof(text))
    return start + @countof(text)
}

#[Swag.Compiler]
func appendPatchFields(buffer: [*] u8, start: u64, type: typeinfo)->u64
{
    let typeStruct = cast(const *Swag.TypeInfoStruct) type
    var len        = start

    foreach field in typeStruct.fields
    {
        len = appendAst(buffer, len, "has_")
        len = appendAst(buffer, len, field.name)
        len = appendAst(buffer, len, ": bool\n")
        len = appendAst(buffer, len, field.name)
        len = appendAst(buffer, len, ": ")
        len = appendAst(buffer, len, field.pointedType.name)
        len = appendAst(buffer, len, "\n")
    }

    return len
}

struct(T) ApiPatch
{
    #ast
    {
        var buffer: [4096] u8
        var len = appendPatchFields(&buffer[0], 0, #typeof(T))
        if len == 0 do
            return ""
        return cast(string) @mkslice(&buffer[0], len)
    }
}

func(T) clearPatch(patch: &ApiPatch'T)
{
    #ast
    {
        var buffer: [4096] u8
        var len = 0'u64
        let typeStruct = cast(const *Swag.TypeInfoStruct) #typeof(T)
        foreach field in typeStruct.fields
        {
            len = appendAst(&buffer[0], len, "patch.has_")
            len = appendAst(&buffer[0], len, field.name)
            len = appendAst(&buffer[0], len, " = false\n")
        }
        if len == 0 do
            return ""
        return cast(string) @mkslice(&buffer[0], len)
    }
}

func(T) capturePatch(patch: &ApiPatch'T, value: const &T)
{
    #ast
    {
        var buffer: [4096] u8
        var len = 0'u64
        let typeStruct = cast(const *Swag.TypeInfoStruct) #typeof(T)
        foreach field in typeStruct.fields
        {
            len = appendAst(&buffer[0], len, "patch.has_")
            len = appendAst(&buffer[0], len, field.name)
            len = appendAst(&buffer[0], len, " = true\n")
            len = appendAst(&buffer[0], len, "patch.")
            len = appendAst(&buffer[0], len, field.name)
            len = appendAst(&buffer[0], len, " = value.")
            len = appendAst(&buffer[0], len, field.name)
            len = appendAst(&buffer[0], len, "\n")
        }
        if len == 0 do
            return ""
        return cast(string) @mkslice(&buffer[0], len)
    }
}

func(T) patchChangedCount(patch: const &ApiPatch'T)->s32
{
    var count: s32
    #ast
    {
        var buffer: [4096] u8
        var len = 0'u64
        let typeStruct = cast(const *Swag.TypeInfoStruct) #typeof(T)
        foreach field in typeStruct.fields
        {
            len = appendAst(&buffer[0], len, "if patch.has_")
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

func(T) patchChangedMask(patch: const &ApiPatch'T)->u64
{
    var mask = 0'u64
    var bit = 1'u64
    #ast
    {
        var buffer: [4096] u8
        var len = 0'u64
        let typeStruct = cast(const *Swag.TypeInfoStruct) #typeof(T)
        foreach field in typeStruct.fields
        {
            len = appendAst(&buffer[0], len, "if patch.has_")
            len = appendAst(&buffer[0], len, field.name)
            len = appendAst(&buffer[0], len, " do\n")
            len = appendAst(&buffer[0], len, "    mask |= bit\n")
            len = appendAst(&buffer[0], len, "bit <<= 1\n")
        }
        if len == 0 do
            return ""
        return cast(string) @mkslice(&buffer[0], len)
    }
    return mask
}

func(T) applyPatch(patch: const &ApiPatch'T, base: T)->T
{
    var result = base
    #ast
    {
        var buffer: [4096] u8
        var len = 0'u64
        let typeStruct = cast(const *Swag.TypeInfoStruct) #typeof(T)
        foreach field in typeStruct.fields
        {
            len = appendAst(&buffer[0], len, "if patch.has_")
            len = appendAst(&buffer[0], len, field.name)
            len = appendAst(&buffer[0], len, " do\n")
            len = appendAst(&buffer[0], len, "    result.")
            len = appendAst(&buffer[0], len, field.name)
            len = appendAst(&buffer[0], len, " = patch.")
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
    let base: TenantSettings =
    {
        seatLimit: 25,
        storageGb: 250,
        auditRetentionDays: 30,
        ssoEnabled: false,
        billingEmail: "billing@acme.test",
        tier: .Growth,
    }

    var patch: ApiPatch'TenantSettings
    patch.has_storageGb = true
    patch.storageGb = 750
    patch.has_ssoEnabled = true
    patch.ssoEnabled = true
    patch.has_billingEmail = true
    patch.billingEmail = "ops@acme.test"

    let updated = applyPatch'(TenantSettings)(patch, base)

    @assert(patchChangedCount'(TenantSettings)(patch) == 3)
    @assert(patchChangedMask'(TenantSettings)(patch) == 26'u64)
    @assert(updated.seatLimit == 25)
    @assert(updated.storageGb == 750)
    @assert(updated.auditRetentionDays == 30)
    @assert(updated.ssoEnabled)
    @assert(updated.billingEmail == "ops@acme.test")
    @assert(updated.tier == .Growth)
    @assert(base.storageGb == 250)
    @assert(!base.ssoEnabled)
    @assert(base.billingEmail == "billing@acme.test")
}

#test
{
    let source: TenantSettings =
    {
        seatLimit: 120,
        storageGb: 2000,
        auditRetentionDays: 365,
        ssoEnabled: true,
        billingEmail: "finance@northwind.test",
        tier: .Enterprise,
    }

    var patch: ApiPatch'TenantSettings
    capturePatch'(TenantSettings)(&patch, source)

    let blank: TenantSettings =
    {
        seatLimit: 0,
        storageGb: 0,
        auditRetentionDays: 0,
        ssoEnabled: false,
        billingEmail: "",
        tier: .Starter,
    }

    let rebuilt = applyPatch'(TenantSettings)(patch, blank)

    @assert(patchChangedCount'(TenantSettings)(patch) == 6)
    @assert(patchChangedMask'(TenantSettings)(patch) == 63'u64)
    @assert(rebuilt.seatLimit == 120)
    @assert(rebuilt.storageGb == 2000)
    @assert(rebuilt.auditRetentionDays == 365)
    @assert(rebuilt.ssoEnabled)
    @assert(rebuilt.billingEmail == "finance@northwind.test")
    @assert(rebuilt.tier == .Enterprise)

    clearPatch'(TenantSettings)(&patch)
    @assert(patchChangedCount'(TenantSettings)(patch) == 0)
    @assert(patchChangedMask'(TenantSettings)(patch) == 0'u64)
}

#test
{
    let base: NotificationPolicy =
    {
        dailyDigest: true,
        weeklyReport: false,
        escalationMinutes: 45,
        smsEnabled: false,
    }

    var patch: ApiPatch'NotificationPolicy
    patch.has_weeklyReport = true
    patch.weeklyReport = true
    patch.has_escalationMinutes = true
    patch.escalationMinutes = 15

    let updated = applyPatch'(NotificationPolicy)(patch, base)

    @assert(patchChangedCount'(NotificationPolicy)(patch) == 2)
    @assert(patchChangedMask'(NotificationPolicy)(patch) == 6'u64)
    @assert(updated.dailyDigest)
    @assert(updated.weeklyReport)
    @assert(updated.escalationMinutes == 15)
    @assert(!updated.smsEnabled)
}
