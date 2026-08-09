#global namespace Swag

// Symbol information decoded from the target-neutral `.swagdbg` section emitted by the linker.
struct __SwagSym
{
    found:   bool   = false
    hasLine: bool   = false
    name:    string = ""
    file:    string = ""
    line:    u32    = 0
}

var __dbgCacheBase:    #null *void  = null
var __dbgCacheSection: #null [*] u8 = null
var __dbgCacheCount:   u32          = 0
var __dbgCacheValid:   bool         = false

func __dbgU32(p: [*] u8, off: u64)->u32 => dref cast(*u32) &p[off]

func __dbgFindSection(base: #null *void)
{
    __dbgCacheBase    = base
    __dbgCacheValid   = false
    __dbgCacheSection = null
    __dbgCacheCount   = 0
    if base == null do
        return

    let section = __hostDebugSection(base)
    if !section do
        return

    __dbgCacheSection = section
    __dbgCacheCount   = __dbgU32(section!, 8)
    __dbgCacheValid   = true
}

func __dbgStr(off: u32)->string
{
    if off == 0 do
        return ""

    let sec = __dbgCacheSection!
    let p   = cast([*] u8) &sec[cast(u64) off]
    return @mkstring(p, @countof(cast(cstring) p))
}

func __symbolize(addr: *void)->__SwagSym
{
    var result: __SwagSym

    let imageBase = __hostImageBaseForAddress(addr)
    if !imageBase do
        return result
    if imageBase != __dbgCacheBase do
        __dbgFindSection(imageBase)
    if !__dbgCacheValid do
        return result

    let rva = cast(u32) (cast(u64) addr - cast(u64) imageBase)
    let sec = __dbgCacheSection!
    for [i] in __dbgCacheCount
    {
        let entry = 16 + cast(u64) i * 20
        let start = __dbgU32(sec, entry)
        let size  = __dbgU32(sec, entry + 4)
        if rva >= start and rva < start + size
        {
            result.found = true
            result.name  = __dbgStr(__dbgU32(sec, entry + 8))
            let fileOffset = __dbgU32(sec, entry + 12)
            if fileOffset != 0
            {
                result.hasLine = true
                result.file    = __dbgStr(fileOffset)
                result.line    = __dbgU32(sec, entry + 16)
            }

            return result
        }
    }

    return result
}

func __logStackTrace(wh: [..] *void, startAfter: #null *Swag.SourceCodeLocation = null, printNoLine = true)
{
    var hasStarted = false

    for [i] in @countof(wh)
    {
        let info = __symbolize(wh[i])
        if !info.hasLine and !printNoLine do
            continue

        if !hasStarted and startAfter
        {
            if !info.hasLine do
                continue
            if startAfter.lineStart != info.line do
                continue
            let afterName = startAfter.fileName
            if @countof(info.file) != @countof(afterName) do
                continue

            var samePath = true
            if afterName != null
            {
                for [it] in @countof(info.file)
                {
                    if info.file[it] == afterName[it] do
                        continue
                    if info.file[it] == '\\' and afterName[it] == '/' do
                        continue
                    if info.file[it] == '/' and afterName[it] == '\\' do
                        continue
                    samePath = false
                    break
                }
            }

            if !samePath do
                continue
            hasStarted = true
            continue
        }

        hasStarted = true
        if info.found do
            @print(info.name)
        if info.hasLine
        {
            @print(" --> ")
            @print(info.file, ":", info.line)
        }

        @print("\n")
    }
}
