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

var __dbgCacheBase:    *void?  = null
var __dbgCacheSection: [*] u8? = null
var __dbgCacheDecoded: [*] u8? = null
var __dbgCacheSize:    u64     = 0
var __dbgCacheCount:   u32     = 0
var __dbgCacheValid:   bool    = false

func __dbgU32(p: [*] u8, off: u64)->u32 => cast(const *u32, (&p[off]))[]

func readDebugString(section: [*] u8, size: u64, stringsOffset, offset: u32, value: *string)->bool
{
    if not offset
    {
        value[] = ""
        return true
    }

    var start = cast(u64, offset)
    if start < stringsOffset or start >= size do
        return false
    var length = 0'u64
    while start + length < size and section[start + length]
    {
        length += 1
    }

    if start + length == size do
        return false
    value[] = Swag.makeString(&section[start], length)
    return true
}

func validateDebugSection(section: [*] u8, size: u64)->bool
{
    if size < 16 or __dbgU32(section, 0) != 0x4244_5753 or __dbgU32(section, 4) != 1 do
        return false

    let count         = cast(u64, __dbgU32(section, 8))
    let stringsOffset = __dbgU32(section, 12)
    let entriesStart  = 16'u64
    let entriesSize   = count * 20
    if entriesSize > size - entriesStart or
       cast(u64, stringsOffset) < entriesStart + entriesSize or
       cast(u64, stringsOffset) > size do
        return false

    for index in count
    {
        let entry  = entriesStart + index * 20
        let start  = cast(u64, __dbgU32(section, entry))
        let length = cast(u64, __dbgU32(section, entry + 4))
        if start + length > 0x1_0000_0000 do
            return false
        let nameOffset = __dbgU32(section, entry + 8)
        let fileOffset = __dbgU32(section, entry + 12)
        if (nameOffset and (nameOffset < stringsOffset or cast(u64, nameOffset) >= size)) or
           (fileOffset and (fileOffset < stringsOffset or cast(u64, fileOffset) >= size)) do
            return false
    }

    return true
}

func __dbgFindSection(base: *void?)
{
    __hostReleaseDecodedDebugSection(__dbgCacheDecoded)
    __dbgCacheBase    = base
    __dbgCacheValid   = false
    __dbgCacheSection = null
    __dbgCacheDecoded = null
    __dbgCacheSize    = 0
    __dbgCacheCount   = 0
    if base == null do
        return

    var encodedSize: u64
    let encoded = __hostDebugSection(base, &encodedSize)
    if not encoded do
        return

    var decodedSize: u64
    let section = __hostDecodeDebugSection(encoded, encodedSize, &decodedSize)
    if not section do
        return
    if not validateDebugSection(section, decodedSize)
    {
        __hostReleaseDecodedDebugSection(section == encoded ? null : section)
        return
    }

    __dbgCacheSection = section
    if section != encoded do
        __dbgCacheDecoded = section
    __dbgCacheSize  = decodedSize
    __dbgCacheCount = __dbgU32(section, 8)
    __dbgCacheValid = true
}

func __symbolize(addr: *void)->__SwagSym
{
    var result: __SwagSym

    let imageBase = __hostImageBaseForAddress(addr)
    if not imageBase do
        return result
    if imageBase != __dbgCacheBase do
        __dbgFindSection(imageBase)
    if not __dbgCacheValid do
        return result

    let relativeAddress = cast(u64, addr) - cast(u64, imageBase)
    if relativeAddress > Swag.U32.Max do
        return result
    let rva = cast(u32, relativeAddress)
    let sec = unwrap __dbgCacheSection
    for i in __dbgCacheCount
    {
        let entry = 16 + cast(u64, i) * 20
        let start = __dbgU32(sec, entry)
        let size  = __dbgU32(sec, entry + 4)
        if cast(u64, rva) >= start and cast(u64, rva) < cast(u64, start) + size
        {
            let stringsOffset = __dbgU32(sec, 12)
            if not readDebugString(sec, __dbgCacheSize, stringsOffset, __dbgU32(sec, entry + 8), &result.name) do
                return __SwagSym{}
            let fileOffset = __dbgU32(sec, entry + 12)
            if fileOffset and not readDebugString(sec, __dbgCacheSize, stringsOffset, fileOffset, &result.file) do
                return __SwagSym{}
            result.found = true
            if fileOffset != 0
            {
                result.hasLine = true
                result.line    = __dbgU32(sec, entry + 16)
            }

            return result
        }
    }

    return result
}

// Reports whether at least one captured address belongs to a Swag symbol table.
//
// Native release artifacts may deliberately carry no such table. In that case an empty heading
// says only that symbolization was unavailable, so the panic report leaves the whole section out.
func __hasStackTraceSymbols(wh: const [..] (*void?))->bool
{
    for address in wh where address and __symbolize(address).found do
        return true
    return false
}

func __logStackTrace(wh: const [..] (*void?), startAfter: *Swag.SourceCodeLocation? = null, printNoLine = true)
{
    var hasStarted = false

    for i in wh.count
    {
        if not wh[i] do
            continue
        let info = __symbolize(unwrap wh[i])
        if not info.found do
            continue
        if not info.hasLine and not printNoLine do
            continue

        if not hasStarted and startAfter
        {
            if not info.hasLine do
                continue
            if startAfter.lineStart != info.line do
                continue
            let afterName = startAfter.fileName
            if info.file.count != afterName.count do
                continue

            var samePath = true
            if afterName != null
            {
                for it in info.file.count
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

            if not samePath do
                continue
            hasStarted = true
            continue
        }

        hasStarted = true
        Swag.print(info.name)
        if info.hasLine
        {
            Swag.print(" --> ")
            Swag.print(info.file, ":", info.line)
        }

        Swag.print("\n")
    }
}
