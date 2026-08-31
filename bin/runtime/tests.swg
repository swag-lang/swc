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
    Swag.getContext().panic = null
    __printPanicReport(message, loc)
    g_TestFailed = true
    __hostTestResume()
}

// Records a hardware exception delivered by the host for the active test thread.
func __testHardwareException(code: u32, instructionAddress: u64, accessKind: u64, accessAddress: u64)
{
    Swag.print("\n#test stops on hardware exception ", cast(s64) code, "\n")
    Swag.print("#test faulting instruction address ", instructionAddress, "\n")
    let symbol = __symbolize(cast(*void) instructionAddress)
    if symbol.hasLine do
        Swag.print("#test faulting symbol ", symbol.name, " (", symbol.file, ":", symbol.line, ")\n")
    elif symbol.found do
        Swag.print("#test faulting symbol ", symbol.name, "\n")
    if code == 0xC0000005 and (accessKind == 0 or accessKind == 1 or accessKind == 8)
    {
        let operation = accessKind == 0 ? "read" : accessKind == 1 ? "write" : "execute"
        Swag.print("#test attempted to ", operation, " address ", accessAddress, "\n")
    }

    g_TestFailed = true
    __hostTestResume()
}

// A test executable launched without the `swag.test` run argument behaves like an application:
// every #test is skipped and #main runs on a state no test has touched.
func __isTestRun()->bool
{
    for arg in Swag.args() where Swag.stringCmp(arg, "swag.test") do
        return true
    return false
}

// The compiler normalizes both sides before launching the artifact. Matching here keeps the
// executable independent of a particular invocation's file filters.
func __isTestFileSelected(path: string)->bool
{
    let prefix    = "swag.test-file="
    var hasFilter = false

    for arg in Swag.args()
    {
        if arg.count < prefix.count or Swag.memcmp(arg.buffer, prefix.buffer, prefix.count) do
            continue

        hasFilter = true
        let filterCount = arg.count - prefix.count
        if filterCount > path.count do
            continue
        if !filterCount do
            return true

        for offset in path.count - filterCount + 1
        {
            if !Swag.memcmp(path.buffer + offset, arg.buffer + prefix.count, filterCount) do
                return true
        }
    }

    return !hasFilter
}

// Repeated tag filters form a union. An untagged test is selected only when no tag filter exists.
func __isTestTagSelected(tag: string)->bool
{
    let prefix    = "swag.test-tag="
    var hasFilter = false

    for arg in Swag.args()
    {
        if arg.count < prefix.count or Swag.memcmp(arg.buffer, prefix.buffer, prefix.count) do
            continue

        hasFilter = true
        let filter = Swag.makeString(arg.buffer + prefix.count, arg.count - prefix.count)
        if Swag.stringCmp(tag, filter) do
            return true
    }

    return !hasFilter
}

// Optimizations stay off: recovery re-enters this function with the registers captured before the
// test ran, so every local must live on the stack rather than in a register the call could reuse.
#[Swag.Optimize(false)]
func __runTest(fn: *void, name: const [*] u8, path: const [*] u8, tag: const [*] u8)
{
    if !__isTestRun() do
        return

    let testName = Swag.makeString(name, (cast(const cstring) name).count)
    let testPath = Swag.makeString(path, (cast(const cstring) path).count)
    let testTag  = Swag.makeString(tag, (cast(const cstring) tag).count)
    if !__isTestFileSelected(testPath) or !__isTestTagSelected(testTag) do
        return

    Swag.print("[swag.test] event=start executed=", cast(s64) g_TestsExecuted, " failed=", cast(s64) g_TestsFailedCnt, " name=", testName, "\n")

    g_TestsExecuted += 1
    g_TestFailed    = false
    g_TestThreadId  = __hostCurrentThreadId()

    let cxt            = Swag.getContext()
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

    Swag.print("[swag.test] event=", g_TestFailed ? "fail" : "pass", " executed=", cast(s64) g_TestsExecuted, " failed=", cast(s64) g_TestsFailedCnt, " name=", testName, "\n")
}

func __testsDone()
{
    if !__isTestRun() do
        return

    // Marker parsed by the compiler's test command to report the native tally.
    Swag.print("[swag.test] executed=", cast(s64) g_TestsExecuted, " failed=", cast(s64) g_TestsFailedCnt, "\n")
    if g_TestsFailedCnt do
        __exitError()
}
