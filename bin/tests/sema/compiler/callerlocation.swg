#global fileprivate
using Swag

// =========================================================================
// Basic: parameter default captures caller function name
// =========================================================================

func captureLoc(loc = #callerlocation)->SourceCodeLocation => loc

func basicCaller()->SourceCodeLocation
{
    return captureLoc()
}

const BasicLoc  = #run basicCaller()
const BasicDecl = #location(basicCaller)
#assert(BasicLoc.funcName == BasicDecl.funcName)
#assert(BasicLoc.fileName != null)

// =========================================================================
// Verify line/col: the location covers the call expression
// =========================================================================

func spanCaller()->SourceCodeLocation
{
    return captureLoc()
}

const SpanLoc = #run spanCaller()
#assert(SpanLoc.lineEnd == SpanLoc.lineStart)

// =========================================================================
// Multiple parameters: #callerlocation as last param with other defaults
// =========================================================================

func multiParam(a: s32, b: s32 = 10, loc = #callerlocation)->SourceCodeLocation => loc

func multiParamCaller()->SourceCodeLocation
{
    return multiParam(42)
}

const MultiLoc = #run multiParamCaller()
#assert(MultiLoc.funcName == #location(multiParamCaller).funcName)

// =========================================================================
// #callerlocation as the first default param
// =========================================================================

func locFirst(loc = #callerlocation, extra: s32 = 0)->SourceCodeLocation => loc

func locFirstCaller()->SourceCodeLocation
{
    return locFirst()
}

const LocFirstResult = #run locFirstCaller()
#assert(LocFirstResult.funcName == #location(locFirstCaller).funcName)

// =========================================================================
// Chained calls: callerLoc reflects the immediate caller, not the root
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

const ChainLoc  = #run chainC()
const ChainDecl = #location(chainB)
#assert(ChainLoc.funcName == ChainDecl.funcName)

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

const MethodLoc = #run methodCaller()
#assert(MethodLoc.funcName == #location(methodCaller).funcName)

// =========================================================================
// Inline function with #callerlocation propagates correctly
// =========================================================================

#[Swag.Inline]
func inlineCapture(loc = #callerlocation)->SourceCodeLocation => loc

#[Swag.Inline]
func inlineMiddle()->SourceCodeLocation
{
    return inlineCapture()
}

const InlineMiddleDecl = #location(inlineMiddle)

#test
{
    let loc = inlineMiddle()
    @assert(loc.funcName == InlineMiddleDecl.funcName)
}

// =========================================================================
// Multiple #callerlocation params in different functions called in sequence
// =========================================================================

func locA(loc = #callerlocation)->SourceCodeLocation => loc
func locB(loc = #callerlocation)->SourceCodeLocation => loc

struct LocPair { a: SourceCodeLocation; b: SourceCodeLocation }

func sequenceCaller()->LocPair
{
    var result: LocPair
    result.a = locA()
    result.b = locB()
    return result
}

const SeqResult = #run sequenceCaller()
#assert(SeqResult.a.funcName == SeqResult.b.funcName)
#assert(SeqResult.a.lineStart < SeqResult.b.lineStart)

// =========================================================================
// Explicit argument overrides #callerlocation default
// =========================================================================

#test
{
    var custom: SourceCodeLocation
    custom.lineStart = 999
    let loc = captureLoc(custom)
    @assert(loc.lineStart == 999)
}

// =========================================================================
// #callerlocation with named arguments
// =========================================================================

func namedArgFunc(a: s32 = 0, loc = #callerlocation, b: s32 = 0)->SourceCodeLocation => loc

func namedArgCaller()->SourceCodeLocation
{
    return namedArgFunc(b: 5, a: 3)
}

const NamedArgLoc = #run namedArgCaller()
#assert(NamedArgLoc.funcName == #location(namedArgCaller).funcName)

// =========================================================================
// fileName field is non-null and consistent across calls
// =========================================================================

func fileCheckA(loc = #callerlocation)->SourceCodeLocation => loc
func fileCheckB(loc = #callerlocation)->SourceCodeLocation => loc

func fileConsistencyCaller()->LocPair
{
    var result: LocPair
    result.a = fileCheckA()
    result.b = fileCheckB()
    return result
}

const FileResult = #run fileConsistencyCaller()
#assert(FileResult.a.fileName != null)
#assert(FileResult.a.fileName == FileResult.b.fileName)

// =========================================================================
// colEnd >= colStart for a single-line call
// =========================================================================

const ColCheckLoc = #run captureLoc()
#assert(ColCheckLoc.colEnd >= ColCheckLoc.colStart)

// =========================================================================
// Error: #callerlocation used outside parameter default
// =========================================================================

#test { const bad = #callerlocation } // swc-expected-error {{sema_err_caller_location_default_only}}
#test { var bad = #callerlocation }   // swc-expected-error {{sema_err_caller_location_default_only}}
