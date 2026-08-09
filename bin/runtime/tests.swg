#global namespace Swag

// Native #test bookkeeping. The host supplies only context recovery and hardware-fault hooks;
// selection, reporting, and the decision to continue with the next test stay platform-neutral.
var g_TestFailed:     bool
var g_TestRunning:    bool
var g_TestThreadId:   u64
var g_TestsExecuted:  u32
var g_TestsFailedCnt: u32

func __testPanicHandler(message: #null string, loc: Swag.SourceCodeLocation)
{
    // Drop the hook first so a panic raised while printing takes the default path.
    @getcontext().panic = null
    __printPanicReport(message, loc)
    g_TestFailed = true
    __hostTestResume()
}

// Records a hardware exception delivered by the host for the active test thread.
func __testHardwareException(code: u32)
{
    @print("\n#test stops on hardware exception ", cast(s64) code, "\n")
    g_TestFailed = true
    __hostTestResume()
}

// A test executable launched without the `swag.test` run argument behaves like an application:
// every #test is skipped and #main runs on a state no test has touched.
func __isTestRun()->bool
{
    for arg in @args where @stringcmp(arg, "swag.test") do
        return true
    return false
}

// Optimizations stay off: recovery re-enters this function with the registers captured before the
// test ran, so every local must live on the stack rather than in a register the call could reuse.
#[Swag.Optimize(false)]
func __runTest(fn: *void)
{
    if !__isTestRun() do
        return

    g_TestsExecuted += 1
    g_TestFailed    = false
    g_TestThreadId  = __hostCurrentThreadId()

    let cxt            = @getcontext()
    let previousPanic  = cxt.panic
    let previousFilter = __hostTestInstallHardwareFilter()
    cxt.panic = cast() &__testPanicHandler

    g_TestRunning = true
    __hostTestCall(fn)
    g_TestRunning = false

    cxt.panic = previousPanic
    __hostTestRestoreHardwareFilter(previousFilter)

    if g_TestFailed do
        g_TestsFailedCnt += 1
}

func __testsDone()
{
    if !__isTestRun() do
        return

    // Marker parsed by the compiler's test command to report the native tally.
    @print("[swag.test] executed=", cast(s64) g_TestsExecuted, " failed=", cast(s64) g_TestsFailedCnt, "\n")
    if g_TestsFailedCnt do
        __exitError()
}
