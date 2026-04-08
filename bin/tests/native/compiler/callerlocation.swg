#global fileprivate
using Swag

// =========================================================================
// Basic: runtime call captures the calling function name
// =========================================================================

func captureLoc(loc = #callerlocation)->SourceCodeLocation => loc

func basicCaller()->SourceCodeLocation
{
    return captureLoc()
}

#test
{
    let loc = basicCaller()
    @assert(loc.funcName == "basicCaller")
    @assert(loc.lineStart == 12)
    @assert(loc.colStart == 12)
    @assert(loc.fileName != null)
}

// =========================================================================
// Chained calls: location reflects the immediate caller
// =========================================================================

func chainA(loc = #callerlocation)->SourceCodeLocation => loc

func chainB()->SourceCodeLocation
{
    return chainA()
}

func chainC()->SourceCodeLocation
{
    return chainB()
}

#test
{
    let loc = chainC()
    @assert(loc.funcName == "chainB")
}

// =========================================================================
// Multiple params with #callerlocation
// =========================================================================

func multiParam(a: s32, b: s32 = 10, loc = #callerlocation)->SourceCodeLocation => loc

func multiParamCaller()->SourceCodeLocation
{
    return multiParam(42)
}

#test
{
    let loc = multiParamCaller()
    @assert(loc.funcName == "multiParamCaller")
}

// =========================================================================
// #callerlocation as the first default param
// =========================================================================

func locFirst(loc = #callerlocation, extra: s32 = 0)->SourceCodeLocation => loc

func locFirstCaller()->SourceCodeLocation
{
    return locFirst()
}

#test
{
    let loc = locFirstCaller()
    @assert(loc.funcName == "locFirstCaller")
}

// =========================================================================
// Explicit argument overrides the default
// =========================================================================

#test
{
    var custom: SourceCodeLocation
    custom.lineStart = 999
    custom.funcName = "custom"
    let loc = captureLoc(custom)
    @assert(loc.lineStart == 999)
    @assert(loc.funcName == "custom")
}

// =========================================================================
// Struct method with #callerlocation
// =========================================================================

struct Tracker
{
    value: s32
}

impl Tracker
{
    mtd getLoc(loc = #callerlocation)->SourceCodeLocation => loc
}

func methodCaller()->SourceCodeLocation
{
    var t = Tracker{value: 1}
    return t.getLoc()
}

#test
{
    let loc = methodCaller()
    @assert(loc.funcName == "methodCaller")
}

// =========================================================================
// Inline function with #callerlocation
// =========================================================================

#[Swag.Inline]
func inlineCapture(loc = #callerlocation)->SourceCodeLocation => loc

#[Swag.Inline]
func inlineMiddle()->SourceCodeLocation
{
    return inlineCapture()
}

#test
{
    let loc = inlineMiddle()
    @assert(loc.funcName == "inlineMiddle")
}

// =========================================================================
// Double inline: both layers inlined
// =========================================================================

#[Swag.Inline]
func doubleInlineInner(loc = #callerlocation)->SourceCodeLocation => loc

#[Swag.Inline]
func doubleInlineOuter()->SourceCodeLocation
{
    return doubleInlineInner()
}

func doubleInlineCaller()->SourceCodeLocation
{
    return doubleInlineOuter()
}

#test
{
    let loc = doubleInlineCaller()
    @assert(loc.funcName == "doubleInlineOuter")
}

// =========================================================================
// Multiple calls in sequence have different line numbers
// =========================================================================

func locCapture(loc = #callerlocation)->SourceCodeLocation => loc

struct LocPair { a: SourceCodeLocation; b: SourceCodeLocation }

func sequenceCaller()->LocPair
{
    var result: LocPair
    result.a = locCapture()
    result.b = locCapture()
    return result
}

#test
{
    let pair = sequenceCaller()
    @assert(pair.a.funcName == pair.b.funcName)
    @assert(pair.a.lineStart < pair.b.lineStart)
}

// =========================================================================
// fileName is consistent across different calls in the same file
// =========================================================================

func fileCheckA(loc = #callerlocation)->SourceCodeLocation => loc
func fileCheckB(loc = #callerlocation)->SourceCodeLocation => loc

func fileCaller()->LocPair
{
    var result: LocPair
    result.a = fileCheckA()
    result.b = fileCheckB()
    return result
}

#test
{
    let pair = fileCaller()
    @assert(pair.a.fileName != null)
    @assert(pair.a.fileName == pair.b.fileName)
}

// =========================================================================
// colEnd >= colStart on a single-line call
// =========================================================================

#test
{
    let loc = captureLoc()
    @assert(loc.colEnd >= loc.colStart)
    @assert(loc.lineStart == loc.lineEnd)
}

// =========================================================================
// Named arguments: #callerlocation still captures correctly
// =========================================================================

func namedArgFunc(a: s32 = 0, loc = #callerlocation, b: s32 = 0)->SourceCodeLocation => loc

func namedArgCaller()->SourceCodeLocation
{
    return namedArgFunc(b: 5, a: 3)
}

#test
{
    let loc = namedArgCaller()
    @assert(loc.funcName == "namedArgCaller")
}

// =========================================================================
// #run block at compile time captures the right location
// =========================================================================

func runTarget(loc = #callerlocation)->SourceCodeLocation => loc

func runCaller()
{
    #run
    {
        let loc = runTarget()
        @assert(loc.funcName == "runCaller")
    }
}

// =========================================================================
// #callerlocation with #run returning a value
// =========================================================================

func jitCapture(loc = #callerlocation)->SourceCodeLocation => loc

func jitCaller()->SourceCodeLocation
{
    return jitCapture()
}

const JitResult = #run jitCaller()
#assert(JitResult.funcName == #location(jitCaller).funcName)

// =========================================================================
// Multiple #callerlocation parameters in different positions
// =========================================================================

func twoLocParams(x: s32, loc = #callerlocation, y: s32 = 0)->SourceCodeLocation => loc

func twoLocCaller()->SourceCodeLocation
{
    return twoLocParams(1)
}

#test
{
    let loc = twoLocCaller()
    @assert(loc.funcName == "twoLocCaller")
}

// =========================================================================
// Recursive call: each level captures its own caller
// =========================================================================

func recursiveCapture(depth: s32, loc = #callerlocation)->SourceCodeLocation
{
    if depth <= 0 do
        return loc
    return recursiveCapture(depth - 1)
}

func recursiveCaller()->SourceCodeLocation
{
    return recursiveCapture(3)
}

#test
{
    let loc = recursiveCaller()
    // depth > 0, so it recurses - the final loc is from recursiveCapture calling itself
    @assert(loc.funcName == "recursiveCapture")
}

#test
{
    // depth == 0, so it returns immediately with the caller's location
    let loc = recursiveCapture(0)
    @assert(loc.fileName != null)
}
