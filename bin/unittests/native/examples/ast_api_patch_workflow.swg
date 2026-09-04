#global private

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
    Swag.memcpy(buffer + start, text.buffer, text.count)
    return start + text.count
}

#[Swag.Compiler]
func appendPatchFields(buffer: [*] u8, start: u64, type: typeinfo)->u64
{
    let typeStruct = cast(const *Swag.TypeInfoStruct) type
    var len        = start

    for field in typeStruct.fields
    {
        len = appendAst(buffer, len, "has_")
        len = appendAst(buffer, len, field.name!)
        len = appendAst(buffer, len, ": bool\n")
        len = appendAst(buffer, len, field.name!)
        len = appendAst(buffer, len, ": ")
        len = appendAst(buffer, len, field.pointedType!.name!)
        if field.pointedType == string do
            len = appendAst(buffer, len, "?")
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
        return cast(string) Swag.makeSlice(&buffer[0], len)
    }
}

func(T) clearPatch(patch: *ApiPatch'T)
{
    #ast
    {
        var buffer: [4096] u8
        var len        = 0'u64
        let typeStruct = cast(const *Swag.TypeInfoStruct) #typeof(T)
        for field in typeStruct.fields
        {
            len = appendAst(&buffer[0], len, "patch.has_")
            len = appendAst(&buffer[0], len, field.name!)
            len = appendAst(&buffer[0], len, " = false\n")
        }
        if len == 0 do
            return ""
        return cast(string) Swag.makeSlice(&buffer[0], len)
    }
}

func(T) capturePatch(patch: *ApiPatch'T, value: T)
{
    #ast
    {
        var buffer: [4096] u8
        var len        = 0'u64
        let typeStruct = cast(const *Swag.TypeInfoStruct) #typeof(T)
        for field in typeStruct.fields
        {
            len = appendAst(&buffer[0], len, "patch.has_")
            len = appendAst(&buffer[0], len, field.name!)
            len = appendAst(&buffer[0], len, " = true\n")
            len = appendAst(&buffer[0], len, "patch.")
            len = appendAst(&buffer[0], len, field.name!)
            len = appendAst(&buffer[0], len, " = value.")
            len = appendAst(&buffer[0], len, field.name!)
            len = appendAst(&buffer[0], len, "\n")
        }
        if len == 0 do
            return ""
        return cast(string) Swag.makeSlice(&buffer[0], len)
    }
}

func(T) patchChangedCount(patch: ApiPatch'T)->s32
{
    var count: s32
    #ast
    {
        var buffer: [4096] u8
        var len        = 0'u64
        let typeStruct = cast(const *Swag.TypeInfoStruct) #typeof(T)
        for field in typeStruct.fields
        {
            len = appendAst(&buffer[0], len, "if patch.has_")
            len = appendAst(&buffer[0], len, field.name!)
            len = appendAst(&buffer[0], len, " do\n")
            len = appendAst(&buffer[0], len, "    count += 1\n")
        }
        if len == 0 do
            return ""
        return cast(string) Swag.makeSlice(&buffer[0], len)
    }
    return count
}

func(T) patchChangedMask(patch: ApiPatch'T)->u64
{
    var mask = 0'u64
    var bit  = 1'u64
    #ast
    {
        var buffer: [4096] u8
        var len        = 0'u64
        let typeStruct = cast(const *Swag.TypeInfoStruct) #typeof(T)
        for field in typeStruct.fields
        {
            len = appendAst(&buffer[0], len, "if patch.has_")
            len = appendAst(&buffer[0], len, field.name!)
            len = appendAst(&buffer[0], len, " do\n")
            len = appendAst(&buffer[0], len, "    mask |= bit\n")
            len = appendAst(&buffer[0], len, "bit <<= 1\n")
        }
        if len == 0 do
            return ""
        return cast(string) Swag.makeSlice(&buffer[0], len)
    }
    return mask
}

func(T) applyPatch(patch: ApiPatch'T, base: T)->T
{
    var result = base
    #ast
    {
        var buffer: [4096] u8
        var len        = 0'u64
        let typeStruct = cast(const *Swag.TypeInfoStruct) #typeof(T)
        for field in typeStruct.fields
        {
            len = appendAst(&buffer[0], len, "if patch.has_")
            len = appendAst(&buffer[0], len, field.name!)
            len = appendAst(&buffer[0], len, " do\n")
            len = appendAst(&buffer[0], len, "    result.")
            len = appendAst(&buffer[0], len, field.name!)
            len = appendAst(&buffer[0], len, " = patch.")
            len = appendAst(&buffer[0], len, field.name!)

            // A 'string?' field needs the assertion on the generated read.
            if field.pointedType == string do
                len = appendAst(&buffer[0], len, "!")
            len = appendAst(&buffer[0], len, "\n")
        }
        if len == 0 do
            return ""
        return cast(string) Swag.makeSlice(&buffer[0], len)
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
        tier: .Growth
        }

    var patch: ApiPatch'TenantSettings
    patch.has_storageGb    = true
    patch.storageGb        = 750
    patch.has_ssoEnabled   = true
    patch.ssoEnabled       = true
    patch.has_billingEmail = true
    patch.billingEmail     = "ops@acme.test"

    let updated = applyPatch'(TenantSettings)(patch, base)

    Swag.assert(patchChangedCount'(TenantSettings)(patch) == 3)
    Swag.assert(patchChangedMask'(TenantSettings)(patch) == 26'u64)
    Swag.assert(updated.seatLimit == 25)
    Swag.assert(updated.storageGb == 750)
    Swag.assert(updated.auditRetentionDays == 30)
    Swag.assert(updated.ssoEnabled)
    Swag.assert(updated.billingEmail == "ops@acme.test")
    Swag.assert(updated.tier == .Growth)
    Swag.assert(base.storageGb == 250)
    Swag.assert(!base.ssoEnabled)
    Swag.assert(base.billingEmail == "billing@acme.test")
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
        tier: .Enterprise
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
        tier: .Starter
        }

    let rebuilt = applyPatch'(TenantSettings)(patch, blank)

    Swag.assert(patchChangedCount'(TenantSettings)(patch) == 6)
    Swag.assert(patchChangedMask'(TenantSettings)(patch) == 63'u64)
    Swag.assert(rebuilt.seatLimit == 120)
    Swag.assert(rebuilt.storageGb == 2000)
    Swag.assert(rebuilt.auditRetentionDays == 365)
    Swag.assert(rebuilt.ssoEnabled)
    Swag.assert(rebuilt.billingEmail == "finance@northwind.test")
    Swag.assert(rebuilt.tier == .Enterprise)

    clearPatch'(TenantSettings)(&patch)
    Swag.assert(patchChangedCount'(TenantSettings)(patch) == 0)
    Swag.assert(patchChangedMask'(TenantSettings)(patch) == 0'u64)
}

#test
{
    let base: NotificationPolicy =
        {
        dailyDigest: true,
        weeklyReport: false,
        escalationMinutes: 45,
        smsEnabled: false
        }

    var patch: ApiPatch'NotificationPolicy
    patch.has_weeklyReport      = true
    patch.weeklyReport          = true
    patch.has_escalationMinutes = true
    patch.escalationMinutes     = 15

    let updated = applyPatch'(NotificationPolicy)(patch, base)

    Swag.assert(patchChangedCount'(NotificationPolicy)(patch) == 2)
    Swag.assert(patchChangedMask'(NotificationPolicy)(patch) == 6'u64)
    Swag.assert(updated.dailyDigest)
    Swag.assert(updated.weeklyReport)
    Swag.assert(updated.escalationMinutes == 15)
    Swag.assert(!updated.smsEnabled)
}
