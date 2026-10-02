#global public

private var opaqueDrops  = 0
private var opaqueCopies = 0
private var opaqueMoves  = 0
private var opaqueTrace  = 0

private struct OpaqueLifecyclePayload
{
    id:    s32
    armed: bool
}

impl OpaqueLifecyclePayload
{
    private mtd opDrop()
    {
        if .armed
        {
            opaqueDrops += 1
            opaqueTrace = opaqueTrace * 10 + .id
        }
    }

    private mtd opPostCopy()
    {
        if .armed
        {
            opaqueCopies += 1
            opaqueTrace  = opaqueTrace * 10 + .id
        }
    }

    private mtd opPostMove()
    {
        if .armed
        {
            opaqueMoves += 1
            opaqueTrace = opaqueTrace * 10 + .id
        }
    }
}

#[Swag.Opaque]
struct OpaqueLifecycleOwner
{
    private payload: OpaqueLifecyclePayload
}

impl OpaqueLifecycleOwner
{
    #[Swag.NoInline]
    mtd arm() { .payload.id = 1; .payload.armed = true }

    #[Swag.NoInline]
    mtd const isArmed()->bool => .payload.armed
}

#[Swag.Opaque]
struct OpaqueLifecycleOrdered
{
    private
    {
        first:  OpaqueLifecyclePayload
        second: OpaqueLifecyclePayload
        armed:  bool
    }
}

impl OpaqueLifecycleOrdered
{
    #[Swag.NoInline]
    mtd arm()
    {
        .first.id     = 1
        .second.id    = 2
        .first.armed  = true
        .second.armed = true
        .armed        = true
    }

    #[Swag.NoInline]
    mtd const isArmed()->bool => .armed

    #[Swag.NoInline]
    mtd opDrop()
    {
        if .armed do
            opaqueTrace = opaqueTrace * 10 + 3
    }

    #[Swag.NoInline]
    mtd opPostCopy()
    {
        if .armed do
            opaqueTrace = opaqueTrace * 10 + 4
    }

    #[Swag.NoInline]
    mtd opPostMove()
    {
        if .armed do
            opaqueTrace = opaqueTrace * 10 + 5
    }
}

#[Swag.NoCopy]
private struct OpaqueLifecycleExclusivePayload
{
    value: s32
}

#[Swag.Opaque]
struct OpaqueLifecycleNoCopy
{
    private payload: OpaqueLifecycleExclusivePayload
}

impl OpaqueLifecycleNoCopy
{
    #[Swag.NoInline]
    mtd arm() { .payload.value = 7 }

    #[Swag.NoInline]
    mtd const isArmed()->bool => .payload.value == 7
}

private struct OpaqueLifecycleObserverPayload
{
    value: s32
}

impl OpaqueLifecycleObserverPayload
{
    private mtd opDrop() { depBorrowAnnotatedObserve() }
}

#[Swag.Opaque]
struct OpaqueLifecycleObserver
{
    private payload: OpaqueLifecycleObserverPayload
}

#[Swag.NoInline]
func opaqueLifecycleReset()
{
    opaqueDrops  = 0
    opaqueCopies = 0
    opaqueMoves  = 0
    opaqueTrace  = 0
}

#[Swag.NoInline]
func opaqueLifecycleDrops()->s32 => opaqueDrops

#[Swag.NoInline]
func opaqueLifecycleCopies()->s32 => opaqueCopies

#[Swag.NoInline]
func opaqueLifecycleMoves()->s32 => opaqueMoves

#[Swag.NoInline]
func opaqueLifecycleTrace()->s32 => opaqueTrace

#[Swag.NoInline]
func opaqueLifecycleSourceControl()->s32
{
    opaqueLifecycleReset()
    {
        var value: OpaqueLifecycleOwner
        value.arm()
        Swag.assert(value.isArmed())
    }
    return opaqueDrops
}
