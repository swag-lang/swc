#global public

using Core

private var g_InitCount:    u32
private var g_PreMainCount: u32
private var g_DropCounter:  *u32?
private var g_ArgumentCount: u64
private var g_ArgumentHash:  u64

private func argumentFingerprint(arguments: const [..] string)->u64
{
    var hash = 0xCBF29CE484222325'u64
    for argument in arguments
    {
        for byte in cast(const [..] u8, argument)
        {
            hash ^= cast(u64, byte)
            hash *= #wrap 0x100000001B3'u64
        }

        hash ^= 0xFF'u64
        hash *= #wrap 0x100000001B3'u64
    }

    return hash
}

#init
{
    g_InitCount += 1
    #static if #os == Swag.TargetOs.Linux
    {
        let arguments = Swag.args()
        g_ArgumentCount = arguments.count
        g_ArgumentHash  = argumentFingerprint(arguments)
    }
}

#premain
{
    g_PreMainCount += 1
}

#drop
{
    #static if #os == Swag.TargetOs.Linux
    {
        // Unloading the provider still sees the executable's original argument storage.
        let arguments = Swag.args()
        Swag.assert(arguments.count == g_ArgumentCount)
        Swag.assert(argumentFingerprint(arguments) == g_ArgumentHash)
        var foundLibraryPath = false
        const Prefix = "--dynamic-runtime-library="
        for argument in arguments where argument.count > Prefix.count and argument[0 until Prefix.count] == Prefix do
            foundLibraryPath = true
        Swag.assert(foundLibraryPath)
    }

    if g_DropCounter
    {
        let counter = unwrap g_DropCounter
        counter[] += 1
    }
}

// Calls into an imported module that raises, then catches that failure back in this DLL.
func ctxDynamicCatchesCoreFailure()->bool
{
    var raisedOutcome: Swag.Error
    discard catch File.info("C:/swag-dynamic-runtime-context-missing-file") as raisedOutcome
    let raised = raisedOutcome.value()
    return raised != null
}

func ctxDynamicLifecycleCounts()->u64 => cast(u64, g_InitCount) | cast(u64, g_PreMainCount) << 32

func ctxDynamicSetDropCounter(counter: *u32)
{
    g_DropCounter = counter
}

func ctxDynamicReadContext()->*Swag.Context => Swag.getContext()
