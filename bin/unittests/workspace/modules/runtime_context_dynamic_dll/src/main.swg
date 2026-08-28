#global public

using Core

private var g_InitCount:    u32
private var g_PreMainCount: u32
private var g_DropCounter:  #null *u32

#init
{
    g_InitCount += 1
}

#premain
{
    g_PreMainCount += 1
}

#drop
{
    if g_DropCounter
    {
        let counter = g_DropCounter!
        counter[] += 1
    }
}

// Calls into an imported module that raises, then catches that failure back in this DLL.
func ctxDynamicCatchesCoreFailure()->bool
{
    discard catch File.info("C:/swag-dynamic-runtime-context-missing-file") as raised
    return raised != null
}

func ctxDynamicLifecycleCounts()->u64 => cast(u64) g_InitCount | cast(u64) g_PreMainCount << 32

func ctxDynamicSetDropCounter(counter: *u32)
{
    g_DropCounter = counter
}
