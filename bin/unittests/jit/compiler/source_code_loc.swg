#global fileprivate

func jitCaptureLoc(loc = #callerlocation)->Swag.SourceCodeLocation => loc

func jitCallerLoc()->Swag.SourceCodeLocation
{
    return jitCaptureLoc()
}

const JitCallerDecl = #location(jitCallerLoc)
const JitCallerLoc  = #run jitCallerLoc()
#assert(JitCallerLoc.fileName == JitCallerDecl.fileName)
#assert(JitCallerLoc.funcName != null)
#assert(JitCallerLoc.funcName == JitCallerDecl.funcName)
#assert(JitCallerLoc.lineStart == 7)
#assert(JitCallerLoc.colStart == 12)
