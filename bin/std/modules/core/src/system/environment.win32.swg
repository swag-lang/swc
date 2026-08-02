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
        catch GetMonitorInfoA(hMonitor, &mi) else do
            return TRUE

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
    let w0   = getSystemMetric(.DesktopWidth)
    let prev = SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE)
    let w1   = getSystemMetric(.DesktopWidth)
    discard SetThreadDpiAwarenessContext(prev)
    return cast(f32) w1 / cast(f32) w0
}

// Handles a native window paint request.
public alias WindowPaintCallback = func||(*Window)

// Handles a native window resize and receives the new logical client size.
public alias WindowResizeCallback = func||(*Window, s32, s32)

// Groups the optional callbacks dispatched by a [[Core.Env.Window]].
public struct WindowCallbacks
{
    onPaint:  #null WindowPaintCallback      // Invoked for a paint request.
    onResize: #null WindowResizeCallback     // Invoked after the logical client size changes.
}

// Configures native window creation.
public struct WindowOptions
{
    className:   string                                                            // Unique native window-class name.
    title:       string                                                            // Initial window title.
    width:       s32                                                               // Width in logical units.
    height:      s32                                                               // Height in logical units.
    x:           s32 = CW_USEDEFAULT                                               // Initial horizontal position in logical units.
    y:           s32 = CW_USEDEFAULT                                               // Initial vertical position in logical units.
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
public struct WindowLoop
{
    maxTestFrames: u32 = 50     // Frame limit used only when `swag.test` is present.

    internal
    {
        testFrames: u32
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
        let createParam  = notnull createStruct.lpCreateParams
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
public func createWindow(options: WindowOptions)->Window fail
{
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

    // Resizes the logical client area while preserving the current position.
    mtd setClientSize(width, height: s32) fail
    {
        var windowRect: RECT
        var clientRect: RECT
        if !GetWindowRect(.nativeHandle, &windowRect) do
            failWinError(GetLastError())
        if !GetClientRect(.nativeHandle, &clientRect) do
            failWinError(GetLastError())

        let frameWidth  = (windowRect.right - windowRect.left) - (clientRect.right - clientRect.left)
        let frameHeight = (windowRect.bottom - windowRect.top) - (clientRect.bottom - clientRect.top)
        try MoveWindow(.nativeHandle, windowRect.left, windowRect.top, width + frameWidth, height + frameHeight, FALSE)
    }

    // Shows the window and updates its client area.
    mtd show() fail
    {
        ShowWindow(.nativeHandle, .showCommand)
        try UpdateWindow(.nativeHandle)
    }
}

public impl WindowLoop
{
    // Processes pending messages and returns whether the application should continue.
    mtd next()->bool
    {
        if Env.hasArgument("swag.test") and .testFrames >= .maxTestFrames do
            return false

        if !processWindowMessages() do
            return false

        if Env.hasArgument("swag.test") do
            .testFrames += 1

        return true
    }
}
