#global private

struct Tracked
{
    value: u64
}

impl Tracked
{
    mtd opDrop()
    {
        Swag.assert(.value == 42)
        .value = 0
    }
}

struct LocalCleanupError
{
    using base: Swag.BaseError
    code:       s32 = 0
}

#[Swag.NoInline]
func makeTracked()->Tracked
{
    var result: retval
    result.value = 42
    return result
}

#[Swag.NoInline]
func localHandle(value: u64)->u64 => value

#[Swag.NoInline]
func mayFail(ok: bool) fail
{
    if not ok do
        fail LocalCleanupError{base: Swag.BaseError{"body"}, code: 2}
}

// The same shapes as the provider's, written beside their caller: a cleanup body reaches both of
// them twice, so nothing either of them materializes may be carried from one exit to the other.
#[Swag.Inline]
func localScaled(value: u64)->u64 => localHandle(value) * 3

#[Swag.Inline]
func localRelease(handle: u64)->u64 fail
{
    let native = localHandle(handle)
    if native == cast #bit (u64) -1 do
        fail LocalCleanupError{base: Swag.BaseError{"cleanup"}, code: 1}
    return native
}

var g_Released: u64

// The deferred statement applies to both the failure of 'mayFail' and the normal end of the
// function, so it is emitted twice and expands both inlined helpers again.
func runLocal(ok: bool) fail
{
    let tracked = makeTracked()

    defer
    {
        g_Released += localScaled(7)
        discard catch localRelease(tracked.value)
    }

    try mayFail(ok)
}

func runCrossFile(ok: bool) fail
{
    let tracked = makeTracked()

    defer
    {
        g_Released += InlineDeferReemission.scaled(7)
        discard catch InlineDeferReemission.release(tracked.value)
    }

    try mayFail(ok)
}

#test
{
    g_Released = 0

    try runLocal(true)
    Swag.assert(g_Released == 21)

    discard catch runLocal(false)
    Swag.assert(g_Released == 42)
}

#test
{
    g_Released = 0

    try runCrossFile(true)
    Swag.assert(g_Released == 21)

    discard catch runCrossFile(false)
    Swag.assert(g_Released == 42)
}
