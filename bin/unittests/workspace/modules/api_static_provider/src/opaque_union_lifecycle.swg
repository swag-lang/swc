#global public

private var opaqueUnionDrops  = 0
private var opaqueUnionCopies = 0
private var opaqueUnionMoves  = 0

private struct OpaqueUnionLifecyclePayload
{
    armed: bool
}

impl OpaqueUnionLifecyclePayload
{
    private mtd opDrop()
    {
        if .armed do
            opaqueUnionDrops += 1
    }

    private mtd opPostCopy()
    {
        if .armed do
            opaqueUnionCopies += 1
    }

    private mtd opPostMove()
    {
        if .armed do
            opaqueUnionMoves += 1
    }
}

// One owning alternative avoids any question about selecting overlapping owners.
#[Swag.Opaque]
union OpaqueUnionLifecycleOwner
{
    private payload: OpaqueUnionLifecyclePayload
}

impl OpaqueUnionLifecycleOwner
{
    #[Swag.NoInline]
    mtd arm() { .payload.armed = true }

    #[Swag.NoInline]
    mtd const isArmed()->bool => .payload.armed
}

#[Swag.NoInline]
func opaqueUnionLifecycleReset()
{
    opaqueUnionDrops  = 0
    opaqueUnionCopies = 0
    opaqueUnionMoves  = 0
}

#[Swag.NoInline]
func opaqueUnionLifecycleDrops()->s32 => opaqueUnionDrops

#[Swag.NoInline]
func opaqueUnionLifecycleCopies()->s32 => opaqueUnionCopies

#[Swag.NoInline]
func opaqueUnionLifecycleMoves()->s32 => opaqueUnionMoves

#[Swag.NoInline]
func opaqueUnionLifecycleSourceDrop()->bool
{
    opaqueUnionLifecycleReset()
    {
        var value: OpaqueUnionLifecycleOwner
        value.arm()
        Swag.assert(value.isArmed())
    }
    return opaqueUnionDrops == 1
}

#[Swag.NoInline]
func opaqueUnionLifecycleSourceCopy()->bool
{
    opaqueUnionLifecycleReset()
    {
        var first: OpaqueUnionLifecycleOwner
        first.arm()
        let second = first
        Swag.assert(first.isArmed() and second.isArmed())
    }
    return opaqueUnionCopies == 1 and opaqueUnionDrops == 2
}

#[Swag.NoInline]
func opaqueUnionLifecycleSourceMove()->bool
{
    opaqueUnionLifecycleReset()
    {
        var first: OpaqueUnionLifecycleOwner
        first.arm()
        let second = #move first
        Swag.assert(not first.isArmed() and second.isArmed())
    }
    return opaqueUnionMoves == 1 and opaqueUnionDrops == 1
}

private union(T) OpaqueUnionLifecycleGeneric
{
    payload: T
}

// Generic instances retain complete callbacks for their owning member.
#[Swag.NoInline]
func opaqueUnionLifecycleGenericControl()->bool
{
    let info = cast(const *Swag.TypeInfoStruct, #typeof(OpaqueUnionLifecycleGeneric'OpaqueUnionLifecyclePayload))
    if info.opDrop == null or info.opPostCopy == null or info.opPostMove == null do
        return false

    opaqueUnionLifecycleReset()
    {
        var first: OpaqueUnionLifecycleGeneric'OpaqueUnionLifecyclePayload
        first.payload.armed = true
        let second = first
        let third  = #move first
        Swag.assert(not first.payload.armed and second.payload.armed and third.payload.armed)
    }
    return opaqueUnionCopies == 1 and opaqueUnionMoves == 1 and opaqueUnionDrops == 2
}
