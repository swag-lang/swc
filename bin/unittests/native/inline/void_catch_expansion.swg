#global private

struct NativeError
{
    using base: Swag.BaseError
    code:       s32 = 0
}

var g_Released: u64
var g_Unmapped: u64

#[Swag.NoInline]
func processId()->u32 => 7

#[Swag.NoInline]
func lastError()->u32 => 5

#[Swag.NoInline]
func closeNativeHandle(handle: u64) { g_Released += 1 }

#[Swag.NoInline]
func raiseNativeError(code: u32) fail
{
    fail NativeError{base: Swag.BaseError{"native"}, code: cast(s32) code}
}

// Produces no value, so its expansion records no register. A caller consuming the expansion's
// payload must read that as 'already emitted', not as 'not emitted yet'.
#[Swag.Inline]
func unmapView(address: const [*] void?) fail
{
    g_Unmapped += 1
    if not processId() do
        try raiseNativeError(lastError())
}

struct Region
{
    view:       *void?
    nativeView: *void?
    mapHandle:  u64
    fileHandle: u64
    length:     u64
    valid:      bool
}

impl Region
{
    // The shape of a native cleanup: a swallowed failure, then the handles it guards. A second
    // expansion of the guarded call would repeat its effect and take its failure exit, leaving
    // everything below unreached.
    mtd closeNative()
    {
        if .nativeView
        {
            discard catch unmapView(.nativeView)
            .nativeView = null
            .view       = null
        }

        if .mapHandle
        {
            closeNativeHandle(.mapHandle)
            .mapHandle = 0
        }

        if .fileHandle
        {
            closeNativeHandle(.fileHandle)
            .fileHandle = 0
        }

        .length = 0
        .valid  = false
    }
}

var g_Storage: u64

#test
{
    g_Released = 0
    g_Unmapped = 0

    var region = Region{&g_Storage, &g_Storage, 11, 22, 96, true}
    region.closeNative()

    Swag.assert(g_Unmapped == 1)
    Swag.assert(g_Released == 2)
    Swag.assert(region.nativeView == null)
    Swag.assert(region.view == null)
    Swag.assert(region.mapHandle == 0)
    Swag.assert(region.fileHandle == 0)
    Swag.assert(region.length == 0)
    Swag.assert(not region.valid)
}
