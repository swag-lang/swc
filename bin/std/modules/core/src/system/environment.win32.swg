#global if WINDOWS
#global namespace Env

using Win32

// Native line-ending sequence.
public const LineEnding = "\r\n"

// Returns the normalized path of a well-known system directory.
//
// Under a sandbox this answers inside it, so an application reaches its own scratch copy of
// the documents or application-data folder without knowing anything about the isolation.
//
// Returns an empty string when the directory cannot be resolved.
public func getSpecialDirectory(what: SpecialDirectory)->String
{
    if isSandboxed() do
        return sandboxSpecialDirectory(what)
    return realSpecialDirectory(what)
}

// Returns the normalized path of a well-known system directory on the machine itself,
// ignoring any sandbox.
//
// Reserved for code that genuinely has to reach the real system, such as locating a system
// executable to launch. Anything that reads or writes an application's own data must go
// through [[Env.getSpecialDirectory]] instead, so a test cannot touch the real thing.
public func realSpecialDirectory(what: SpecialDirectory)->String
{
    if what == SpecialDirectory.Temp
    {
        var a: [MAX_PATH] u8
        let len = catch GetTempPathA(MAX_PATH, &a[0]) as err
        if err != null or len >= MAX_PATH do
            return ""

        var result: retval = cast(string) @mkslice(&a[0], cast(u64) len)
        Path.normalize(&result)
        return result
    }

    var a: [MAX_PATH] u8
    var v: s32

    switch #complete what
    {
    case .Temp:           unreachable
    case .Font:           v = CSIDL_FONTS
    case .Desktop:        v = CSIDL_DESKTOP
    case .CommonAppData:  v = CSIDL_COMMON_APPDATA
    case .CommonPictures: v = CSIDL_COMMON_PICTURES
    case .CommonVideos:   v = CSIDL_COMMON_VIDEO
    case .CommonMusic:    v = CSIDL_COMMON_MUSIC
    case .UserAppData:    v = CSIDL_APPDATA
    case .UserDocuments:  v = CSIDL_MYDOCUMENTS
    case .UserPictures:   v = CSIDL_MYPICTURES
    case .UserVideos:     v = CSIDL_MYVIDEO
    case .UserMusic:      v = CSIDL_MYMUSIC
    }

    var result: retval
    catch Win32.SHGetSpecialFolderPathA(null, &a[0], v, FALSE) as err
    if err == null
    {
        result = cast(string) @mkslice(&a[0], @countof(cast(cstring) &a[0]))
        Path.normalize(&result)
    }

    return result
}

// Returns snapshots of all active display monitors, ordered from left to right.
public func getMonitors()->Array'Monitor
{
    var result: retval

    func proc(hMonitor: HMONITOR, _hDC: HDC, _lpRect: *RECT, lParam: LPARAM)->BOOL
    {
        var mi: MONITORINFO

        // Logical bounds are what a DPI-unaware process sees. Force the unaware
        // context for that read so the result stays logical even after the process
        // has opted into per-monitor awareness (see enableDpiAwareness).
        {
            let last = Win32.SetThreadDpiAwarenessContext(Win32.DPI_AWARENESS_CONTEXT_UNAWARE)
            defer discard Win32.SetThreadDpiAwarenessContext(last)
            catch GetMonitorInfoA(hMonitor, &mi) else do
                return TRUE
        }

        var m: Monitor
        let ptr = cast(*Array'Monitor) cast #bit (u64) lParam

        m.bounds.x      = mi.rcMonitor.left
        m.bounds.y      = mi.rcMonitor.top
        m.bounds.width  = mi.rcMonitor.right - mi.rcMonitor.left
        m.bounds.height = mi.rcMonitor.bottom - mi.rcMonitor.top

        m.workArea.x      = mi.rcWork.left
        m.workArea.y      = mi.rcWork.top
        m.workArea.width  = mi.rcWork.right - mi.rcWork.left
        m.workArea.height = mi.rcWork.bottom - mi.rcWork.top

        let last = Win32.SetThreadDpiAwarenessContext(Win32.DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE)
        defer discard Win32.SetThreadDpiAwarenessContext(last)
        catch GetMonitorInfoA(hMonitor, &mi)

        m.scaleFactor = (mi.rcMonitor.right - mi.rcMonitor.left) / m.bounds.width

        m.physicalBounds.x      = mi.rcMonitor.left
        m.physicalBounds.y      = mi.rcMonitor.top
        m.physicalBounds.width  = mi.rcMonitor.right - mi.rcMonitor.left
        m.physicalBounds.height = mi.rcMonitor.bottom - mi.rcMonitor.top

        m.physicalWorkArea.x      = mi.rcWork.left
        m.physicalWorkArea.y      = mi.rcWork.top
        m.physicalWorkArea.width  = mi.rcWork.right - mi.rcWork.left
        m.physicalWorkArea.height = mi.rcWork.bottom - mi.rcWork.top

        ptr.add(m)
        return TRUE
    }

    EnumDisplayMonitors(null, null, cast() &proc, cast #bit (LPARAM) cast(u64) &result)
    result.sort(func||(a, b) { return a.bounds.x <=> b.bounds.x })

    return result
}

// Selects `path` in the platform file explorer.
#[Swag.Discardable]
public func showInFileExplorer(path: string)->bool
{
    var x: String = path
    x.replace("/", "\\")
    x = Format.toString("/select,\"%\"", x)

    let explorer = Utf16.toZeroTerminated("explorer.exe")
    let params   = Utf16.toZeroTerminated(x)
    discard catch ShellExecuteW(null, null, @dataof(explorer), @dataof(params), null, SW_SHOW) as err
    return err == null
}

// Opens `url` with the system's default handler.
public func openUrl(url: string)
{
    discard catch ShellExecuteA(null, null, @dataof(url), null, null, SW_SHOW)
}

// Returns one virtual-desktop metric in physical pixels.
public func getSystemMetric(what: SystemMetric)->s32
{
    switch #complete what
    {
    case .DesktopX:      return GetSystemMetrics(SM_XVIRTUALSCREEN)
    case .DesktopY:      return GetSystemMetrics(SM_YVIRTUALSCREEN)
    case .DesktopWidth:  return GetSystemMetrics(SM_CXVIRTUALSCREEN)
    case .DesktopHeight: return GetSystemMetrics(SM_CYVIRTUALSCREEN)
    }

    unreachable
}

// Returns the user's preferred locale name, such as `"fr-FR"`, or an empty string
// when the system cannot provide one. The part before `-` is the language tag an
// application can hand to its localization layer.
public func userLocaleName()->String
{
    var name16: [LOCALE_NAME_MAX_LENGTH] u16
    let len = catch GetUserDefaultLocaleName(&name16[0], LOCALE_NAME_MAX_LENGTH) as err
    if err != null or len <= 1 do
        return ""

    // The returned length includes the terminating zero.
    return Utf8.fromUtf16(@mkslice(&name16[0], cast(u64) (len - 1)))
}

var g_SysInfo: SYSTEM_INFO
#init
{
    GetSystemInfo(&g_SysInfo)
}

// Register an application in the system
//
// Refused under a sandbox: this writes to the user's registry, which a test or a smoke run
// has no business touching.
public func registerApplication(appName, appFriendly: string)
{
    if denySystemMutation(.ApplicationRegistration) do
        return

    var hKey: HKEY

    let commandKey = Format.toString("Software\\Classes\\Applications\\%", appName)
    if RegCreateKeyExA(HKEY_CURRENT_USER, commandKey.buffer, 0, null, 0, KEY_SET_VALUE, null, &hKey, null) == ERROR_SUCCESS
    {
        RegSetValueExA(hKey, null, 0, REG_SZ, @dataof(appFriendly), cast(u32) (@countof(appFriendly) + 1))
        RegSetValueExA(hKey, @dataof("FriendlyAppName"), 0, REG_SZ, @dataof(appFriendly), cast(u32) (@countof(appFriendly) + 1))
        RegCloseKey(hKey)
    }

    // Register the application properly
    let regAppKey = Format.toString("Software\\RegisteredApplications")
    if RegCreateKeyExA(HKEY_CURRENT_USER, @dataof(regAppKey), 0, null, 0, KEY_SET_VALUE, null, &hKey, null) == ERROR_SUCCESS
    {
        let capabilitiesPath = Format.toString("Software\\Classes\\Applications\\%\\Capabilities", appName)
        RegSetValueExA(hKey, @dataof(appFriendly), 0, REG_SZ, capabilitiesPath.buffer, cast(u32) (capabilitiesPath.length + 1))
        RegCloseKey(hKey)
    }

    // Create capabilities key
    let capKey = Format.toString("Software\\Classes\\Applications\\%\\Capabilities", appName)
    if RegCreateKeyExA(HKEY_CURRENT_USER, @dataof(capKey), 0, null, 0, KEY_SET_VALUE, null, &hKey, null) == ERROR_SUCCESS
    {
        RegSetValueExA(hKey, @dataof("ApplicationName"), 0, REG_SZ, @dataof(appFriendly), cast(u32) (@countof(appFriendly) + 1))

        // RegSetValueExA(hKey, @dataof("ApplicationDescription"), 0, REG_SZ, @dataof(appDescription), cast(u32) (@countof(appDescription) + 1))
        RegCloseKey(hKey)
    }
}

// Associate an extension to an executable
//
// Refused under a sandbox, which reports it as not associated: claiming a file extension
// changes what the shell does on the whole machine.
#[Swag.Discardable]
public func associateFileExtension(extension, appName, appPath: string)->bool
{
    if denySystemMutation(.FileAssociation) do
        return false

    var hKey: HKEY

    /////

    let extKey = Format.toString("Software\\Classes\\%\\OpenWithProgids", extension)
    if RegCreateKeyExA(HKEY_CURRENT_USER, extKey.buffer, 0, null, 0, KEY_SET_VALUE, null, &hKey, null) != ERROR_SUCCESS
    {
        return false
    }

    let valApp = Format.toString("%", appName)
    if RegSetValueExA(hKey, null, 0, REG_SZ, valApp.buffer, cast(u32) (valApp.length + 1)) != ERROR_SUCCESS
    {
        RegCloseKey(hKey)
        return false
    }

    RegCloseKey(hKey)

    /////

    let supportedTypes = Format.toString("Software\\Classes\\Applications\\%\\SupportedTypes", appName)
    if RegCreateKeyExA(HKEY_CURRENT_USER, supportedTypes.buffer, 0, null, 0, KEY_SET_VALUE, null, &hKey, null) != ERROR_SUCCESS
    {
        return false
    }

    if RegSetValueExA(hKey, @dataof(extension), 0, REG_SZ, null, 0) != ERROR_SUCCESS
    {
        RegCloseKey(hKey)
        return false
    }

    RegCloseKey(hKey)

    /////

    let commandKey = Format.toString("Software\\Classes\\Applications\\%\\shell\\open\\command", appName)
    if RegCreateKeyExA(HKEY_CURRENT_USER, commandKey.buffer, 0, null, 0, KEY_SET_VALUE, null, &hKey, null) != ERROR_SUCCESS
    {
        return false
    }

    var command = Format.toString("\"%\" \"%%1\"", appPath)
    command.replace("/", "\\")
    if RegSetValueExA(hKey, null, 0, REG_SZ, command.buffer, cast(u32) (command.length + 1)) != ERROR_SUCCESS
    {
        RegCloseKey(hKey)
        return false
    }

    RegCloseKey(hKey)
    return true
}

// Makes `appPath` the program the shell runs for `extension`, for the current user.
//
// This is the strong form of [[Env.associateFileExtension]]: that one offers the application in
// the *Open with* list and leaves the default alone, which is what an application wants for a
// format it merely reads. This one takes the extension over, so opening one of those files —
// from a double-click, from `cmd`, from anywhere the shell resolves a document — runs `appPath`.
// Reserve it for an extension the application defines.
//
// `progId` is the class name the extension points at, conventionally `Vendor.Kind`. It is what
// distinguishes this claim from another program's, so keep it stable: registering the same
// `progId` again updates the claim instead of adding a second one. `description` is the file
// type as the shell shows it in a folder listing.
//
// The command it registers passes the opened file and then everything else the caller typed, so
// an extension claimed this way carries its own arguments.
//
// Refused under a sandbox, which reports it as not claimed: this changes what the shell does on
// the whole machine.
#[Swag.Discardable]
public func claimFileExtension(extension, progId, description, appPath: string)->bool
{
    if denySystemMutation(.FileAssociation) do
        return false

    var native = String.from(appPath)
    native.replace("/", "\\")

    if !writeUserClassString(Format.toString("Software\\Classes\\%", progId), "", description) do
        return false
    if !writeUserClassString(Format.toString("Software\\Classes\\%\\DefaultIcon", progId), "", Format.toString("%,0", native)) do
        return false
    if !writeUserClassString(Format.toString("Software\\Classes\\%\\shell\\open\\command", progId), "", Format.toString("\"%\" \"%%1\" %%*", native)) do
        return false
    if !writeUserClassString(Format.toString("Software\\Classes\\%", extension), "", progId) do
        return false

    SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, null, null)
    return true
}

// Writes one string under `HKEY_CURRENT_USER\<keyPath>`, creating the key when it is missing.
//
// An empty `valueName` writes the key's default value, which is where the shell reads a class
// name, an icon and a command line. The value is written as UTF-16, so a path that leaves the
// ASCII range survives the round trip.
private func writeUserClassString(keyPath: string, valueName: string, value: string)->bool
{
    let nativeKey = Utf16.toZeroTerminated(keyPath)

    var hKey: HKEY
    if RegCreateKeyExW(HKEY_CURRENT_USER, @dataof(nativeKey), 0, null, 0, KEY_SET_VALUE, null, &hKey, null) != ERROR_SUCCESS do
        return false
    defer RegCloseKey(hKey)

    let nativeValue = Utf16.toZeroTerminated(value)
    let bytes       = cast(u32) (@countof(nativeValue) * #sizeof(u16))

    if @countof(valueName) == 0 do
        return RegSetValueExW(hKey, null, 0, REG_SZ, cast(#null const *u8) @dataof(nativeValue), bytes) == ERROR_SUCCESS

    let nativeName = Utf16.toZeroTerminated(valueName)
    return RegSetValueExW(hKey, @dataof(nativeName), 0, REG_SZ, cast(#null const *u8) @dataof(nativeValue), bytes) == ERROR_SUCCESS
}

var g_StoreArgs: String

func getNativeArgs()->string
{
    let ptr = GetCommandLineW()
    g_StoreArgs = Utf8.fromUtf16(@mkslice(ptr, Utf16.lengthZeroTerminated(ptr)))

    if @countof(@pinfos.args) do
        g_StoreArgs.append(@pinfos.args)

    return g_StoreArgs
}

// Returns the current logical-to-physical desktop scale factor.
public func getDpiScale()->f32
{
    // GetDpiForSystem answers 96 in a DPI-unaware context, so query it under an
    // explicitly aware thread context; the result is then correct whether or not
    // the process itself opted into awareness.
    let prev = SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_SYSTEM_AWARE)
    defer discard SetThreadDpiAwarenessContext(prev)
    return cast(f32) GetDpiForSystem() / cast(f32) USER_DEFAULT_SCREEN_DPI
}

var g_DpiAware: bool

// Declares this process per-monitor DPI aware, so windows receive physical pixels.
//
// Every window-creation path calls this before its first native window exists; an
// application only needs it directly when it creates native windows on its own.
// Once enabled, monitor and cursor coordinates are physical desktop pixels and the
// system no longer stretches window content on scaled displays. Idempotent, and a
// failure (for example when the awareness was already set by other means) is ignored.
public func enableDpiAwareness()
{
    if g_DpiAware do
        return
    g_DpiAware = true
    discard SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)
}

// Handles a native window paint request.
public alias WindowPaintCallback = func||(*Window)

// Handles a native window resize and receives the new client size in physical pixels.
public alias WindowResizeCallback = func||(*Window, s32, s32)

// Groups the optional callbacks dispatched by a [[Core.Env.Window]].
public struct WindowCallbacks
{
    onPaint:  #null WindowPaintCallback      // Invoked for a paint request.
    onResize: #null WindowResizeCallback     // Invoked after the logical client size changes.
}

// Configures native window creation.
//
// `width` and `height` are logical units: the created window is proportionally
// larger, in physical pixels, on a scaled display. The client size reported to
// [[Core.Env.WindowResizeCallback]] is physical.
public struct WindowOptions
{
    className:   string                                                            // Unique native window-class name.
    title:       string                                                            // Initial window title.
    width:       s32                                                               // Width in logical units.
    height:      s32                                                               // Height in logical units.
    x:           s32 = CW_USEDEFAULT                                               // Initial horizontal position in physical desktop pixels.
    y:           s32 = CW_USEDEFAULT                                               // Initial vertical position in physical desktop pixels.
    style:       u32 = WS_OVERLAPPEDWINDOW | WS_CLIPSIBLINGS | WS_CLIPCHILDREN     // Native window style flags.
    exStyle:     u32                                                               // Native extended window style flags.
    classStyle:  u32 = CS_OWNDC                                                    // Native window-class style flags.
    showCommand: s32 = SW_SHOW                                                     // Native command used by [[Core.Env.Window.show]].
}

// Owns one native application window.
//
// Create a window with [[Core.Env.createWindow]]. The value closes any remaining native window
// when it leaves scope; call [[Core.Env.Window.close]] to release it earlier.
#[Swag.NoCopy]
public struct Window
{
    readonly
    {
        nativeHandle: HWND     // Borrowed native handle, or null before creation.
    }

    callbacks: WindowCallbacks     // Callbacks dispatched by the native window procedure.

    internal
    {
        showCommand: s32 = SW_SHOW
    }
}

// Provides iterable native message processing.
// Pumps window messages until the window closes, or until a smoke run's frame budget is spent.
public struct WindowLoop
{
    // Frames a smoke run should render for this program, or zero to take the launcher's budget.
    //
    // A program that cycles through pages knows how many frames it takes to show them all,
    // and that count is a property of its content rather than of whoever launched it. It has
    // no effect on a normal run, which ends only when the window closes.
    smokeFrames: u32

    internal
    {
        frameBudget: u32     // Frames this run may render; zero outside a smoke run.
        framesRun:   u32     // Frames rendered so far.
    }
}

private func getWindowFromHandle(hWnd: HWND)->#null *Window
{
    return cast(#null *Window) cast #bit (u64) GetWindowLongPtrA(hWnd, GWLP_USERDATA)
}

private func envWindowProc(hWnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM)->LRESULT
{
    if msg == WM_CREATE
    {
        let createStruct = cast(*CREATESTRUCTA) cast #bit (u64) lParam
        let createParam  = createStruct.lpCreateParams!
        SetWindowLongPtrA(hWnd, GWLP_USERDATA, cast #bit (LONG_PTR) cast(u64) createParam)

        let window = cast(*Window) createParam
        window.setNativeHandle(hWnd)
    }

    let window = getWindowFromHandle(hWnd)
    if window
    {
        let safeWindow = window
        switch msg
        {
        case WM_PAINT:
            var ps: PAINTSTRUCT
            BeginPaint(hWnd, &ps)
            let onPaint = window.callbacks.onPaint
            if onPaint do
                onPaint(safeWindow)
            EndPaint(hWnd, &ps)
            return 0

        case WM_SIZE:
            let onResize = window.callbacks.onResize
            if onResize do
                onResize(safeWindow, LOWORD(lParam), HIWORD(lParam))
            return 0

        case WM_DPICHANGED:

            // Adopt the physical rectangle the system suggests for the new monitor
            // scale; the ensuing WM_SIZE reports the new physical client size.
            let suggested = cast(const *RECT) cast #bit (u64) lParam
            discard catch SetWindowPos(hWnd, null, suggested.left, suggested.top, suggested.right - suggested.left, suggested.bottom - suggested.top, SWP_NOZORDER | SWP_NOACTIVATE)
            return 0

        case WM_DESTROY:
            PostQuitMessage(0)
            return 0

        case WM_NCDESTROY:
            window.setNativeHandle(null)
            SetWindowLongPtrA(hWnd, GWLP_USERDATA, 0)
        }
    }

    return DefWindowProcA(hWnd, msg, wParam, lParam)
}

impl Window
{
    internal mtd setNativeHandle(nativeHandle: HWND)
    {
        .nativeHandle = nativeHandle
    }

    // Rebinds the native callback state when an owning window value moves.
    mtd opPostMove()
    {
        if .nativeHandle do
            SetWindowLongPtrA(.nativeHandle, GWLP_USERDATA, cast #bit (LONG_PTR) cast(u64) &me)
    }

    // Closes any remaining native window when this value leaves scope.
    mtd opDrop()
    {
        catch .close()
    }
}

// Creates and owns a native application window.
//
// The returned [[Core.Env.Window]] keeps platform-specific state behind
// [[Core.Env.Window.nativeHandle]] and closes the native window when it leaves scope.
// The process becomes DPI aware, and the logical `options` size is realized in the
// physical pixels of the monitor the window appears on.
public func createWindow(options: WindowOptions)->Window fail
{
    // The first native window of the process decides its DPI awareness.
    enableDpiAwareness()

    var result: retval
    result.showCommand = options.showCommand

    var wc: WNDCLASSA
    wc.style         = options.classStyle
    wc.lpfnWndProc   = cast() &envWindowProc
    wc.hInstance     = GetModuleHandleA(null)
    wc.lpszClassName = @dataof(options.className)
    try RegisterClassA(wc)

    let hWnd = CreateWindowExA(options.exStyle, @dataof(options.className), @dataof(options.title), options.style, options.x, options.y, options.width, options.height, null, null, wc.hInstance, &result)
    if !hWnd do
        failWinError(GetLastError())

    result.setNativeHandle(hWnd)

    // The window now knows its monitor: resize it from logical units to physical
    // pixels while it is still hidden.
    let scale = result.dpiScale()
    if scale != 1
    {
        let physWidth  = cast(s32) Math.round(options.width * scale)
        let physHeight = cast(s32) Math.round(options.height * scale)
        catch SetWindowPos(hWnd, null, 0, 0, physWidth, physHeight, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE)
    }

    return result
}

// Processes all pending window messages. Returns false when the application should exit.
public func processWindowMessages()->bool
{
    var msg: MSG
    while PeekMessageA(&msg, null, 0, 0, PM_REMOVE) != 0
    {
        if msg.message == WM_QUIT do
            return false

        TranslateMessage(&msg)
        DispatchMessageA(&msg)
    }

    return true
}

public impl Window
{
    // Closes the native window if it is still open.
    //
    // Calling `close` repeatedly is safe. Failure leaves the native handle owned by this value,
    // so a later call or scope cleanup can retry the release.
    mtd close() fail
    {
        let handle = .nativeHandle
        if !handle do
            return

        try DestroyWindow(handle)
        .nativeHandle = null
    }

    // Acquires the native device context for this window.
    //
    // Every successful call must be paired with
    // [[Core.Env.Window.releaseDeviceContext]] on the same window.
    mtd acquireDeviceContext()->HDC
    {
        return GetDC(.nativeHandle)
    }

    // Releases a device context returned by [[Core.Env.Window.acquireDeviceContext]].
    mtd releaseDeviceContext(deviceContext: HDC)
    {
        ReleaseDC(.nativeHandle, deviceContext)
    }

    // Queues a paint request for this window.
    mtd requestPaint()
    {
        expect PostMessageA(.nativeHandle, WM_PAINT, 0, 0)
    }

    // Returns the physical device pixels per logical unit on the window's monitor.
    mtd const dpiScale()->f32
    {
        if !.nativeHandle do
            return 1
        return cast(f32) GetDpiForWindow(.nativeHandle) / cast(f32) USER_DEFAULT_SCREEN_DPI
    }

    // Resizes the client area to `width` by `height` logical units while preserving
    // the current position.
    //
    // The realized client area is proportionally larger, in physical pixels, on a
    // scaled display; [[Core.Env.WindowResizeCallback]] reports that physical size.
    mtd setClientSize(width, height: s32) fail
    {
        var windowRect: RECT
        var clientRect: RECT
        if !GetWindowRect(.nativeHandle, &windowRect) do
            failWinError(GetLastError())
        if !GetClientRect(.nativeHandle, &clientRect) do
            failWinError(GetLastError())

        let scale       = .dpiScale()
        let physWidth   = cast(s32) Math.round(width * scale)
        let physHeight  = cast(s32) Math.round(height * scale)
        let frameWidth  = (windowRect.right - windowRect.left) - (clientRect.right - clientRect.left)
        let frameHeight = (windowRect.bottom - windowRect.top) - (clientRect.bottom - clientRect.top)
        try MoveWindow(.nativeHandle, windowRect.left, windowRect.top, physWidth + frameWidth, physHeight + frameHeight, FALSE)
    }

    // Shows the window and updates its client area.
    //
    // The resize callback receives the initial physical client size before the
    // window becomes visible, so a renderer never draws a frame at a stale size.
    mtd show() fail
    {
        if .callbacks.onResize
        {
            var clientRect: RECT
            if GetClientRect(.nativeHandle, &clientRect)
            {
                let onResize = .callbacks.onResize!
                onResize(&me, clientRect.right - clientRect.left, clientRect.bottom - clientRect.top)
            }
        }

        ShowWindow(.nativeHandle, .showCommand)
        try UpdateWindow(.nativeHandle)
    }
}

public impl WindowLoop
{
    // Processes pending messages and returns whether the application should continue.
    mtd next()->bool
    {
        // A smoke run is bounded by whoever launched it, so a program driving its own loop
        // stops on its own without recognizing that it is being exercised.
        if .frameBudget == 0
        {
            .frameBudget = Env.smokeFrames()
            if .frameBudget and .smokeFrames do
                .frameBudget = .smokeFrames
        }

        if .frameBudget and .framesRun >= .frameBudget do
            return false

        if !processWindowMessages() do
            return false

        if .frameBudget do
            .framesRun += 1

        return true
    }
}
