#global namespace Tool

using Core

// Native ABI modules are the bottom portability layer. They may depend on one another, but no
// source above an approved host leaf or adapter imports them directly.
private const NativeModules = ["win32", "gdi32", "gdiplus", "xinput", "xaudio2"]

private const NativeInteropRoots = [
    "bin/std/modules/win32/",
    "bin/std/modules/gdi32/",
    "bin/std/modules/gdiplus/",
    "bin/std/modules/xinput/",
    "bin/std/modules/xaudio2/"]

// OpenGL has its own portability contract and is deliberately outside the bin portability
// campaign. This is a named module boundary, not a file-name convention.
private const PortabilityExcludedRoots = [
    "bin/std/modules/ogl/",
    "bin/std/modules/pixel/src/render/ogl/"]

// Each entry owns an irreducible host mechanism, an optional native adapter, or a native
// integration test. Adding a platform suffix does not add a file to this list.
private const NativeSourceFiles = [
    "bin/runtime/os_windows.swg",
    "bin/std/modules/core/src/crypto/security.win32.swg",
    "bin/std/modules/core/src/diagnostics/console.win32.swg",
    "bin/std/modules/core/src/diagnostics/debugger.win32.swg",
    "bin/std/modules/core/src/filesystem/directory.win32.swg",
    "bin/std/modules/core/src/filesystem/file.win32.swg",
    "bin/std/modules/core/src/filesystem/fileattributes.win32.swg",
    "bin/std/modules/core/src/filesystem/fileinfo.win32.swg",
    "bin/std/modules/core/src/filesystem/filestream.win32.swg",
    "bin/std/modules/core/src/filesystem/mappedfile.win32.swg",
    "bin/std/modules/core/src/filesystem/path.win32.swg",
    "bin/std/modules/core/src/filesystem/watcher.win32.swg",
    "bin/std/modules/core/src/input/gamepad.xinput.swg",
    "bin/std/modules/core/src/input/gamepadstate.xinput.swg",
    "bin/std/modules/core/src/input/keyboard.win32.swg",
    "bin/std/modules/core/src/input/keyboardstate.win32.swg",
    "bin/std/modules/core/src/input/mouse.win32.swg",
    "bin/std/modules/core/src/system/environment.win32.swg",
    "bin/std/modules/core/src/system/errors.win32.swg",
    "bin/std/modules/core/src/system/hardware.win32.swg",
    "bin/std/modules/core/src/system/nativelibrary.win32.swg",
    "bin/std/modules/core/src/system/process.win32.swg",
    "bin/std/modules/core/src/system/sandbox.win32.swg",
    "bin/std/modules/core/src/thread/event.win32.swg",
    "bin/std/modules/core/src/thread/mutex.win32.swg",
    "bin/std/modules/core/src/thread/rwlock.win32.swg",
    "bin/std/modules/core/src/thread/thread.win32.swg",
    "bin/std/modules/core/src/time/datetime.win32.swg",
    "bin/std/modules/core/src/time/time.win32.swg",
    "bin/std/modules/core/src/time/timer.win32.swg",
    "bin/std/modules/core/src/tests/thread/job.test.swg",
    "bin/std/modules/core/src/tests/thread/thread.test.swg",
    "bin/std/modules/gui/src/application.win32.swg",
    "bin/std/modules/gui/src/clipboard.win32.swg",
    "bin/std/modules/gui/src/dragdrop.win32.swg",
    "bin/std/modules/gui/src/paint/cursor.win32.swg",
    "bin/std/modules/gui/src/surface.win32.swg",
    "bin/std/modules/gui/src/tests/dragdrop.win32.test.swg",
    "bin/std/modules/pixel/src/image/image.win32.swg",
    "bin/std/modules/pixel/src/tests/image.win32.test.swg",
    "bin/std/modules/pixel/src/text/fontfamily.win32.swg",
    "bin/std/modules/pixel/src/text/typeface.win32.swg",
    "bin/std/modules/audio/src/driver/xaudio2.swg",
    "bin/std/modules/audio/src/tests/driver.xaudio2.win32.test.swg",
    "bin/apps/modules/sSnapForge/src/screenshot/screenshot.win32.swg",
    "bin/apps/modules/sVaultDrive/src/autounmount.win32.swg",
    "bin/apps/modules/sVaultDrive/src/tests/integration.win32.swg"]

// A named backend directory owns every file below it; it is stronger evidence than a suffix and
// lets one backend keep its ABI, callbacks, lifecycle, and integration test together.
private const NativeSourceRoots = ["bin/apps/modules/sVaultDrive/src/winfsp/"]

// These module setup files are the only portable-module wiring points allowed to import a raw
// native module. Each import is conditional on the target OS in the source itself.
private const NativeImportFiles = [
    "bin/std/modules/core/module.swg",
    "bin/std/modules/audio/module.swg"]

// These neutral files select a portable value, test, or backend at compile time. T-298 owns the
// repeated Audio dispatch; new policy does not join this list.
private const OsDispatchFiles = [
    "bin/std/modules/core/module.swg",
    "bin/std/modules/core/src/config.swg",
    "bin/std/modules/core/src/tests/config.test.swg",
    "bin/std/modules/audio/module.swg",
    "bin/std/modules/audio/src/driver/backend.swg"]

private const NativeNamespaces = ["Win32", "Gdi32", "Gdi32Priv", "Gdiplus", "XInput", "XAudio2"]

// Identifiers whose appearance in ordinary code proves that a native representation crossed the
// boundary. Namespace use catches native functions and constants; this list covers unqualified
// ABI types and the public virtual-key adapter tracked by T-287.
private const NativeIdentifiers = [
    "ATOM", "BITMAP", "BITMAPINFO", "BITMAPINFOHEADER", "BLENDFUNCTION", "BOOL", "BOOLEAN",
    "BYTE", "CHAR", "COLORREF", "COMDLG_FILTERSPEC", "CRITICAL_SECTION", "DWORD", "DWORD_PTR",
    "FILETIME", "FORMATETC", "GUID", "HANDLE", "HBITMAP", "HBRUSH", "HCURSOR", "HDC", "HDROP",
    "HFONT", "HGLOBAL", "HICON", "HINSTANCE", "HKEY", "HLOCAL", "HMODULE", "HMONITOR", "HWND",
    "HRESULT", "ICONINFO", "IDataObject", "IDropSource", "IDropTarget", "IEnumFORMATETC", "IStream",
    "LARGE_INTEGER", "LONG", "LONG_PTR", "LPARAM", "LPCSTR", "LPCVOID", "LPCWSTR", "LPSTR", "LPVOID",
    "LPWSTR", "LRESULT", "LOGFONTW", "MSG", "NOTIFYICONDATAA", "OVERLAPPED", "PAINTSTRUCT", "POINT",
    "POINTL", "PROCESS_INFORMATION", "RECT", "SECURITY_ATTRIBUTES", "SIZE", "STARTUPINFOA", "STGMEDIUM",
    "SYSTEM_INFO", "TEXTMETRICW", "UINT", "ULONG", "VirtualKey", "WCHAR", "WIN32_FIND_DATAA",
    "WNDCLASSEXA", "WPARAM", "XINPUT_STATE", "XINPUT_VIBRATION"]

private const NativeIdentifierPrefixes = [
    "DPI_AWARENESS_CONTEXT_", "GWL_", "GWLP_", "SWP_", "VK_", "WM_", "WS_", "XINPUT_"]

// Existing native API adapters are exact declarations, not blanket file approvals. T-109 owns
// the installed-font descriptor; T-287 owns image, surface, and keyboard interoperability.
private const NativeDeclarationApprovals = [
    "bin/std/modules/core/src/input/key.swg",
    "public alias VirtualKey = u32",
    "bin/std/modules/core/src/input/keyboardstate.win32.swg",
    "nativeState: [256] BYTE",
    "bin/std/modules/core/src/input/keyboard.win32.swg",
    "public func keyToVirtualKey(key: Key)->VirtualKey",
    "bin/std/modules/core/src/input/keyboard.win32.swg",
    "public func virtualKeyToKey(vkey: VirtualKey)->Key",
    "bin/std/modules/core/src/system/environment.win32.swg",
    "mtd acquireWin32DeviceContext()->HDC",
    "bin/std/modules/core/src/system/environment.win32.swg",
    "mtd releaseWin32DeviceContext(deviceContext: HDC)",
    "bin/std/modules/core/src/tests/input/key.test.swg",
    "var virtualKey: Input.VirtualKey = 42",
    "bin/std/modules/gui/src/surface.win32.swg",
    "mtd const win32Handle()->HWND => .hWnd",
    "bin/std/modules/pixel/src/image/image.win32.swg",
    "mtd toHicon()->HICON fail",
    "bin/std/modules/pixel/src/image/image.win32.swg",
    "func from(hicon: HICON)->Image fail",
    "bin/std/modules/pixel/src/image/image.win32.swg",
    "func from(hbitmap: HBITMAP)->Image fail",
    "bin/std/modules/pixel/src/text/fontfamily.win32.swg",
    "face: LOGFONTW",
    "bin/std/modules/pixel/src/text/typeface.win32.swg",
    "public func createFromHfont(fullname: string, hfont: HFONT)->*TypeFace fail"]

private struct PortabilityParseState
{
    blockComment:   bool
    multilineText:  bool
    globalPublic:   bool
    pendingOpaque:  bool
    pendingPrivate: bool
    pendingScope:   bool
    pendingPublic:  bool
    privateDepth:   s32
    publicDepth:    s32
    publicStruct:   bool
    publicOpaque:   bool
}

// Runs the source-only portability boundary audit.
public func runPortability(context: *Context, options: *Options)->s32 fail
{
    if !options.module.isEmpty() or !options.command.isEmpty()
    {
        Console.println("portability.swgs checks the whole bin boundary and takes no name or command")
        return 1
    }

    return try auditPortability(context)
}

// Checks that platform-neutral bin sources do not acquire a raw host dependency.
public func auditPortability(context: *Context)->s32 fail
{
    var errors: u32

    for path in NativeSourceFiles
    {
        let fullname = Path.combine(context.root.toString(), path)
        if File.exists(fullname) do
            continue
        Console.println("error: portability approval names missing source ", path)
        errors += 1
    }

    for root in ["bin/runtime", "bin/std/modules", "bin/apps/modules"] do
        errors += try auditPortabilityRoot(context, root)

    if errors != 0
    {
        Console.println("error: portability validation found ", errors, errors == 1 ? " problem" : " problems")
        return 1
    }

    return 0
}

// Checks one source root without walking workspace caches beside it.
private func auditPortabilityRoot(context: *Context, root: string)->u32 fail
{
    var errors: retval
    let directory = Path.combine(context.root.toString(), root)
    let files     = try Directory.enumerateFiles(directory.toString(), ".swg", recurse: true)
    for file in files
    {
        let relative = portabilityRelativePath(context, file.fullname.toString())
        if isUnderAny(relative.toString(), PortabilityExcludedRoots) do
            continue
        errors += try auditPortabilityFile(context, relative.toString())
    }

    return errors
}

private func auditPortabilityFile(context: *Context, path: string)->u32 fail
{
    let fullname = Path.combine(context.root.toString(), path)
    let content  = try File.readAllText(fullname.toString())

    let interop     = isUnderAny(path, NativeInteropRoots)
    let native      = interop or isApprovedPath(path, NativeSourceFiles) or isUnderAny(path, NativeSourceRoots)
    let importPoint = interop or isApprovedPath(path, NativeImportFiles)
    let osDispatch  = native or isApprovedPath(path, OsDispatchFiles)

    var state:  PortabilityParseState
    var errors: u32
    var lineNumber = 0'u64

    for rawLine in Tokenize.splitLines(content.toString())
    {
        lineNumber += 1
        let rawTrimmed = Latin1.trim(rawLine)
        let code       = portabilityCode(rawLine, &state)
        let trimmed    = Latin1.trim(code.toString())
        if @countof(trimmed) == 0 do
            continue

        if Utf8.startsWith(cast(const [..] u8) trimmed, "#global public") do
            state.globalPublic = true

        if Utf8.startsWith(cast(const [..] u8) rawTrimmed, "#import(")
        {
            if hasNativeImport(rawTrimmed) and !importPoint
            {
                reportPortability(path, lineNumber, "platform-neutral source cannot import a native module")
                errors += 1
            }
            elif interop and !hasNativeImport(rawTrimmed)
            {
                reportPortability(path, lineNumber, "native interoperability cannot import a platform-neutral module")
                errors += 1
            }
        }

        if containsText(trimmed, "#os ==") and !osDispatch
        {
            reportPortability(path, lineNumber, "platform-neutral source cannot branch on '#os'")
            errors += 1
        }

        if (containsText(trimmed, "#foreignlib(") or containsText(trimmed, "Swag.Foreign(")) and !native
        {
            reportPortability(path, lineNumber, "platform-neutral source cannot declare a native foreign operation")
            errors += 1
        }

        let nativeNamespace = nativeNamespaceOnLine(trimmed)
        let nativeType      = nativeIdentifierOnLine(trimmed)
        let approvedLine    = isApprovedDeclaration(path, trimmed)
        if !native and !approvedLine and (@countof(nativeNamespace) != 0 or @countof(nativeType) != 0)
        {
            let marker = @countof(nativeNamespace) != 0 ? nativeNamespace : nativeType
            reportPortability(path, lineNumber, Format.toString("platform-neutral source cannot name native identifier '%'", marker).toString())
            errors += 1
        }

        if native do
            errors += auditPublicNativeDeclaration(path, trimmed, lineNumber, nativeType, approvedLine, &state)
        updatePublicScope(trimmed, &state)
    }

    return errors
}

private func auditPublicNativeDeclaration(path: string, line: string, lineNumber: u64, nativeType: string, approved: bool, state: *PortabilityParseState)->u32
{
    if @countof(nativeType) == 0 or approved or state.privateDepth != 0 do
        return 0

    let privateLine = startsWithAccess(line, "private") or startsWithAccess(line, "internal")
    if state.publicDepth == 1
    {
        if state.publicStruct and !state.publicOpaque
        {
            reportPortability(path, lineNumber, Format.toString("portable public field cannot name native type '%'", nativeType).toString())
            return 1
        }

        if !state.publicStruct and !privateLine and isCallableDeclaration(line)
        {
            reportPortability(path, lineNumber, Format.toString("portable public operation cannot name native type '%'", nativeType).toString())
            return 1
        }
    }

    if startsWithAccess(line, "public") and isDeclaration(line)
    {
        reportPortability(path, lineNumber, Format.toString("portable public declaration cannot name native type '%'", nativeType).toString())
        return 1
    }

    if state.globalPublic and !privateLine and isDeclaration(line)
    {
        reportPortability(path, lineNumber, Format.toString("portable public declaration cannot name native type '%'", nativeType).toString())
        return 1
    }

    return 0
}

private func updatePublicScope(line: string, state: *PortabilityParseState)
{
    let opens  = countByte(line, '{')
    let closes = countByte(line, '}')

    if state.pendingScope and opens > closes
    {
        if state.pendingPublic
        {
            state.publicDepth  = cast(s32) opens - cast(s32) closes
            state.publicStruct = false
            state.publicOpaque = false
        }
        else do
            state.privateDepth = cast(s32) opens - cast(s32) closes

        state.pendingScope  = false
        state.pendingPublic = false
        return
    }

    if state.privateDepth != 0
    {
        state.privateDepth += cast(s32) opens - cast(s32) closes
        if state.privateDepth <= 0 do
            state.privateDepth = 0
        return
    }

    if state.pendingPrivate and opens > closes
    {
        state.pendingPrivate = false
        state.privateDepth   = cast(s32) opens - cast(s32) closes
        return
    }

    if state.publicDepth != 0
    {
        state.publicDepth += cast(s32) opens - cast(s32) closes
        if state.publicDepth <= 0
        {
            state.publicDepth  = 0
            state.publicStruct = false
            state.publicOpaque = false
        }

        return
    }

    if containsText(line, "Swag.Opaque")
    {
        state.pendingOpaque = true
        return
    }

    let privateLine = startsWithAccess(line, "private") or startsWithAccess(line, "internal")
    if privateLine and containsText(line, "#[")
    {
        if opens > closes do
            state.privateDepth = cast(s32) opens - cast(s32) closes
        else do
            state.pendingPrivate = true
        state.pendingOpaque = false
        return
    }

    let publicLine = startsWithAccess(line, "public") or state.globalPublic and !privateLine
    let isStruct   = declarationStartsWith(line, "struct")
    let isImpl     = declarationStartsWith(line, "impl")
    if (publicLine or privateLine) and isImpl
    {
        if opens > closes
        {
            if publicLine
            {
                state.publicDepth  = cast(s32) opens - cast(s32) closes
                state.publicStruct = isStruct
                state.publicOpaque = isStruct and state.pendingOpaque
            }
            else do
                state.privateDepth = cast(s32) opens - cast(s32) closes
        }
        else
        {
            state.pendingScope  = true
            state.pendingPublic = publicLine
        }
    }
    elif publicLine and isStruct and opens > closes
    {
        state.publicDepth  = cast(s32) opens - cast(s32) closes
        state.publicStruct = true
        state.publicOpaque = state.pendingOpaque
    }

    if !Utf8.startsWith(cast(const [..] u8) line, "#[") do
        state.pendingOpaque = false
}

private func portabilityCode(line: string, state: *PortabilityParseState)->String
{
    var result: retval
    var quoted  = false
    var escaped = false
    var index   = 0'u64

    while index < @countof(line)
    {
        if state.multilineText
        {
            if index + 2 < @countof(line) and line[index] == '"' and line[index + 1] == '"' and line[index + 2] == '"'
            {
                state.multilineText = false
                index               += 3
            }
            else do
                index += 1
            continue
        }

        if state.blockComment
        {
            if index + 1 < @countof(line) and line[index] == '*' and line[index + 1] == '/'
            {
                state.blockComment = false
                index              += 2
            }
            else do
                index += 1
            continue
        }

        if !quoted and index + 1 < @countof(line) and line[index] == '/' and line[index + 1] == '/' do
            break
        if !quoted and index + 1 < @countof(line) and line[index] == '/' and line[index + 1] == '*'
        {
            state.blockComment = true
            index              += 2
            continue
        }

        if !quoted and index + 2 < @countof(line) and line[index] == '"' and line[index + 1] == '"' and line[index + 2] == '"'
        {
            state.multilineText = true
            result              += ' '
            index               += 3
            continue
        }

        let value = line[index]
        if quoted
        {
            if escaped do
                escaped = false
            elif value == '\\' do
                escaped = true
            elif value == '"' do
                quoted = false
            index += 1
            continue
        }

        if value == '"'
        {
            quoted = true
            result += ' '
        }
        else do
            result += value
        index += 1
    }

    return result
}

private func portabilityRelativePath(context: *Context, fullname: string)->String
{
    let rootLength = @countof(context.root.toString())
    let start      = rootLength < @countof(fullname) and (fullname[rootLength] == '/' or fullname[rootLength] == '\\') ? rootLength + 1 : rootLength
    var result     = String.from(fullname[start until @countof(fullname)])
    result.replace("\\", "/")
    return result
}

private func hasNativeImport(line: string)->bool
{
    for name in NativeModules
    {
        let marker = Format.toString("\"%\"", name)
        if containsText(line, marker.toString()) do
            return true
    }

    return false
}

private func nativeNamespaceOnLine(line: string)->string
{
    let usingLine = Utf8.startsWith(cast(const [..] u8) line, "using ")
    for name in NativeNamespaces
    {
        let qualified = Format.toString("%.", name)
        if containsText(line, qualified.toString()) or usingLine and containsIdentifier(line, name) do
            return name
    }

    return ""
}

private func nativeIdentifierOnLine(line: string)->string
{
    for name in NativeIdentifiers
    {
        if containsIdentifier(line, name) do
            return name
    }

    for prefix in NativeIdentifierPrefixes
    {
        if containsIdentifierPrefix(line, prefix) do
            return prefix
    }

    return ""
}

private func containsIdentifier(text: string, identifier: string)->bool
{
    var offset = 0'u64
    while offset < @countof(text)
    {
        let found = Utf8.indexOf(cast(const [..] u8) text[offset until @countof(text)], identifier)
        if found == Swag.U64.Max do
            return false

        let start  = offset + found
        let end    = start + @countof(identifier)
        let before = start == 0 or !Latin1.isWord(text[start - 1])
        let after  = end == @countof(text) or !Latin1.isWord(text[end])
        if before and after do
            return true
        offset = start + 1
    }

    return false
}

private func containsIdentifierPrefix(text: string, prefix: string)->bool
{
    var offset = 0'u64
    while offset < @countof(text)
    {
        let found = Utf8.indexOf(cast(const [..] u8) text[offset until @countof(text)], prefix)
        if found == Swag.U64.Max do
            return false

        let start = offset + found
        if start == 0 or !Latin1.isWord(text[start - 1]) do
            return true
        offset = start + 1
    }

    return false
}

private func isApprovedDeclaration(path: string, line: string)->bool
{
    for index in @countof(NativeDeclarationApprovals) / 2
    {
        if samePath(path, NativeDeclarationApprovals[index * 2]) and line == NativeDeclarationApprovals[index * 2 + 1] do
            return true
    }

    return false
}

private func isApprovedPath(path: string, approvals: const [..] string)->bool
{
    for approved in approvals
    {
        if samePath(path, approved) do
            return true
    }

    return false
}

private func isUnderAny(path: string, roots: const [..] string)->bool
{
    for root in roots
    {
        if Utf8.startsWith(cast(const [..] u8) path, root, .Latin1NoCase) do
            return true
    }

    return false
}

private func samePath(left: string, right: string)->bool
{
    return Latin1.compare(left, right, ignoreCase: true) == 0
}

private func containsText(text: string, value: string)->bool
{
    return Utf8.indexOf(cast(const [..] u8) text, value) != Swag.U64.Max
}

private func startsWithAccess(line: string, access: string)->bool
{
    let marker = Format.toString("% ", access)
    return Utf8.startsWith(cast(const [..] u8) line, marker.toString())
}

private func declarationStartsWith(line: string, kind: string)->bool
{
    var declaration = line
    for access in ["public", "private", "internal"]
    {
        let marker = Format.toString("% ", access)
        if Utf8.startsWith(cast(const [..] u8) declaration, marker.toString())
        {
            declaration = Latin1.trim(declaration[@countof(marker.toString()) until @countof(declaration)])
            break
        }
    }

    let marker = Format.toString("% ", kind)
    return Utf8.startsWith(cast(const [..] u8) declaration, marker.toString())
}

private func isCallableDeclaration(line: string)->bool
{
    return declarationStartsWith(line, "func") or declarationStartsWith(line, "mtd")
}

private func isDeclaration(line: string)->bool
{
    return isCallableDeclaration(line) or declarationStartsWith(line, "alias") or declarationStartsWith(line, "struct") or declarationStartsWith(line, "enum") or declarationStartsWith(line, "interface")
}

private func countByte(text: string, value: u8)->u64
{
    var result = 0'u64
    for byte in text
    {
        if byte == value do
            result += 1
    }

    return result
}

private func reportPortability(path: string, line: u64, message: string)
{
    Console.println("error: ", path, ":", line, ": ", message)
}
