#global if #os == Swag.TargetOs.Windows

using Win32, Core, Pixel, Win32.Gdi32

// Windows storage embedded by [[Gui.Application]].
#[Swag.Opaque]
struct ApplicationNative
{
    frameTimer: HANDLE
    frameTimerAttempted: bool

    public
    {
        fileSmallIconsImage:     Image         // Strip of the 16-pixel shell icons fetched so far.
        fileSmallIconsImageList: ImageList     // Renderer upload of the small icon strip.
        mapFileSmallIcons:       HashTable!{String, s32}     // Index of each small icon in the strip, by extension or name.

        fileBigIconsImage:     Image         // Strip of the 32-pixel shell icons fetched so far.
        fileBigIconsImageList: ImageList     // Renderer upload of the large icon strip.
        mapFileBigIcons:       HashTable!{String, s32}     // Index of each large icon in the strip, by extension or name.

        hotKeysDisabled: bool     // Whether registered system-wide shortcuts are withdrawn from the desktop.
    }
}

impl Application
{
    internal mtd releaseNativeApplication() { .releaseNativeFrameTimer() }

    internal mtd releaseNativeFrameTimer()
    {
        if .frameTimer
        {
            CloseHandle(.frameTimer)
        }

        .frameTimer = null
    }

    // Quiet windows only poll worker completions once per display-sized interval. Input wakes
    // the native wait directly; gestures, animations and timer deadlines keep their cadence.
    internal mtd nativeFrameWaitMicroseconds(elapsed: u64)->u64
    {
        if .renderingSuspended
        {
            return elapsed < 16000 ? 16000 - elapsed : 0
        }

        if .frameTrace.busyLoop
        {
            return 0
        }

        for surface in .surfaces where not surface.isHidden and not surface.isMinimized
        {
            if surface.isDirty
            {
                return 0
            }
        }

        let active = .mouseCaptureWnd or .animator.activeCount() != 0
        let turnUs = active ? 1000_u64 : 16000_u64
        if elapsed >= turnUs
        {
            return 0
        }

        var waitUs = turnUs - elapsed

        for timer in .timers where not timer.isPendingRemoval
        {
            let periodUs  = timer.periodMilliseconds * 1000
            let elapsedUs = timer.stopwatch.isRunning() ? timer.stopwatch.elapsedMicroseconds() : 0
            if elapsedUs >= periodUs
            {
                return 0
            }

            waitUs = Math.min(waitUs, periodUs - elapsedUs)
        }

        return waitUs
    }

    // Waits for input or the next clock deadline without delaying content that is ready to paint.
    internal mtd waitForNativeFrame(startedAt: u64)
    {
        let waitUs = .nativeFrameWaitMicroseconds(Time.monotonicMicroseconds() - startedAt)
        if not waitUs
        {
            return
        }

        if not .frameTimerAttempted
        {
            .frameTimerAttempted = true
            .frameTimer = CreateWaitableTimerExW(null, null, CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, SYNCHRONIZE | TIMER_MODIFY_STATE)
        }

        if .frameTimer
        {
            let dueTime: LARGE_INTEGER = -cast(s64, waitUs) * 10
            if SetWaitableTimer(.frameTimer, &dueTime, 0, null, null, FALSE)
            {
                var errorOutcome: Swag.Error
                discard catch MsgWaitForMultipleObjectsEx(1, &.frameTimer, 16, QS_ALLINPUT, MWMO_INPUTAVAILABLE) as errorOutcome
                let error = errorOutcome.value()
                if error == null
                {
                    return
                }
            }

            .releaseNativeFrameTimer()
        }

        // Older hosts or an exhausted timer allocation can use the ordinary message wait.
        discard catch MsgWaitForMultipleObjectsEx(0, null, cast(u32, (waitUs + 999) / 1000), QS_ALLINPUT, MWMO_INPUTAVAILABLE)
    }

    internal mtd refreshSystemMotionPreference()
    {
        var animationsEnabled = TRUE
        catch SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &animationsEnabled, 0)
        {
            return
        }

        let wasReduced = .isReducedMotion()
        .systemReducedMotion = not animationsEnabled
        if not wasReduced and .isReducedMotion()
        {
            .animator.finishDecorative()
        }
    }

    // Reads the light or dark setting the user chose for applications, and follows it.
    //
    // Windows keeps it as `AppsUseLightTheme` under the personalization key of the user: zero asks
    // for a dark theme. A missing value is the light default of the system.
    internal mtd refreshSystemAppearance()
    {
        let keyPath   = Utf16.toZeroTerminated("Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize")
        let valueName = Utf16.toZeroTerminated("AppsUseLightTheme")

        var key: HKEY
        if RegOpenKeyExW(HKEY_CURRENT_USER, keyPath.buffer, 0, KEY_QUERY_VALUE, &key) != ERROR_SUCCESS
        {
            .setSystemPrefersLight(true)
            return
        }

        defer discard RegCloseKey(key)

        var value: DWORD = 1
        var size:  DWORD = #sizeof(DWORD)
        var kind:  DWORD
        if RegQueryValueExW(key, valueName.buffer, null, &kind, cast(*BYTE, &value), &size) != ERROR_SUCCESS or kind != REG_DWORD
        {
            value = 1
        }

        .setSystemPrefersLight(value != 0)
    }

    // Samples the desktop pixel currently under the mouse cursor.
    func pickColorAtMouse()->Color
    {
        let awareness = Win32.SetThreadDpiAwarenessContext(Win32.DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE)
        defer discard Win32.SetThreadDpiAwarenessContext(awareness)

        let hdc = GetDC(null)

        var pt: POINT
        GetCursorPos(&pt)
        let col = GetPixel(hdc, pt.x, pt.y) | 0xFF000000

        ReleaseDC(null, hdc)
        return Color.fromAbgr(col)
    }

    internal mtd captureMouse(wnd: *Wnd)
    {
        .mouseCaptureWnd = wnd
        SetCapture(wnd.surface!.native.hWnd)
    }

    internal mtd releaseMouse()
    {
        .mouseCaptureWnd = null
        ReleaseCapture()
    }

    private func hotKeyNativeId(modifiers: Input.KeyModifiers, key: Input.Key)->s32
    {
        var mod: u32
        if modifiers & .Alt
        {
            mod |= MOD_ALT
        }

        if modifiers & .Control
        {
            mod |= MOD_CONTROL
        }

        if modifiers & .Shift
        {
            mod |= MOD_SHIFT
        }

        let winKey = Input.Keyboard.keyToVirtualKey(key)

        var crc32: Hash.Crc32
        crc32.update(Swag.makeSlice(cast(const [*] u8, &mod), 4))
        crc32.update(Swag.makeSlice(cast(const [*] u8, &winKey), 4))
        return cast(s32, (crc32.value() & 0x7FFFFFFF))
    }

    // A system-wide hot key belongs to the desktop of the person running the process, and only one
    // process on the machine can hold a given one. A sandboxed run therefore takes none: the
    // shortcut still enters [[Gui.Application.hotKeys]] and [[Gui.Application.dispatchHotKey]] still routes
    // it, exactly as the fake clipboard keeps clipboard semantics without touching the system one.
    //
    // Failing instead of substituting would defeat the purpose: an application that reports an
    // unavailable shortcut in its own window would paint that report during its own tests, which is
    // the flaky picture this avoids.
    internal func registerNativeHotKey(modifiers: Input.KeyModifiers, key: Input.Key) fail
    {
        if Env.isSandboxed()
        {
            return
        }

        let hotKeyId = hotKeyNativeId(modifiers, key)
        let winKey   = Input.Keyboard.keyToVirtualKey(key)

        var mod: u32
        if modifiers & .Alt
        {
            mod |= MOD_ALT
        }

        if modifiers & .Control
        {
            mod |= MOD_CONTROL
        }

        if modifiers & .Shift
        {
            mod |= MOD_SHIFT
        }

        catch UnregisterHotKey(null, hotKeyId)
        try RegisterHotKey(null, hotKeyId, mod, winKey)
    }

    // Symmetrical to [[Gui.Application.registerNativeHotKey]]: a sandboxed run holds no system hot key to release.
    internal func unregisterNativeHotKey(modifiers: Input.KeyModifiers, key: Input.Key)
    {
        if Env.isSandboxed()
        {
            return
        }

        catch UnregisterHotKey(null, hotKeyNativeId(modifiers, key))
    }

    internal mtd sendHotKey(msg: MSG)
    {
        if .hotKeysDisabled
        {
            return
        }

        using Input
        var modifiers: KeyModifiers
        if msg.lParam & MOD_ALT
        {
            modifiers |= .Alt
        }

        if msg.lParam & MOD_CONTROL
        {
            modifiers |= .Control
        }

        if msg.lParam & MOD_SHIFT
        {
            modifiers |= .Shift
        }

        let key = Keyboard.virtualKeyToKey(cast(VirtualKey, (msg.lParam >> 16)))

        .dispatchHotKey(modifiers, key)
    }

    internal mtd sendSystemEvents()
    {
        if not .renderer.needsNativeWindow()
        {
            return
        }

        var msg: MSG
        while PeekMessageW(&msg, null, 0, 0, PM_REMOVE) != 0
        {
            if msg.message == WM_HOTKEY
            {
                .sendHotKey(msg)
            }
            else
            {
                // The queue exposes each key's state as its message is removed. A press and
                // release in one frame would otherwise look like no change to the snapshot.
                let isKey = msg.message == WM_KEYDOWN or msg.message == WM_KEYUP or
                            msg.message == WM_SYSKEYDOWN or msg.message == WM_SYSKEYUP
                if let source = .nativeFocusSurface where isKey and source.win32Handle() == msg.hwnd
                {
                    .keyboard.update()
                    let modifiers = .keyboard.pressedModifiers()
                    // Control shortcuts do not type into the control they activate. Preserve
                    // Control+Alt translation because Windows also uses it for AltGr.
                    if not modifiers.has(.Control) or modifiers.has(.Alt)
                    {
                        TranslateMessage(&msg)
                    }

                    .dispatchKeyboardChanges()
                }
                else
                {
                    TranslateMessage(&msg)
                }

                DispatchMessageW(&msg)
            }
        }
    }

    internal mtd surfaceAtNative(x, y: f32)->*Surface?
    {
        let pt   = POINT{cast(s32, x), cast(s32, y)}
        let hWnd = WindowFromPoint(pt)
        if hWnd == null
        {
            return null
        }

        for s in .surfaces
        {
            if s.native.hWnd == hWnd
            {
                if not .modalSurfaces.isEmpty() and s != .modalSurfaces.back()
                {
                    return null
                }

                return s
            }
        }

        return null
    }

    internal mtd addIconToImageList(name: string, hIcon: HICON, small: bool)->Icon
    {
        var result: #returntype

        var index:      s32
        var curImg:     *Image
        var curImgList: *ImageList

        if small
        {
            index      = cast(s32, .mapFileSmallIcons.count)
            curImg     = &.fileSmallIconsImage
            curImgList = &.fileSmallIconsImageList
        }
        else
        {
            index      = cast(s32, .mapFileBigIcons.count)
            curImg     = &.fileBigIconsImage
            curImgList = &.fileBigIconsImageList
        }

        let sizeIcon = small ? 16 : 32

        // Convert icon to image
        var errOutcome: Swag.Error
        var img:        #decltype(expect Image.from(hIcon))
        catch { img = try Image.from(hIcon) } as errOutcome
        let err = errOutcome.value()
        defer catch DestroyIcon(hIcon)
        if err != null
        {
            return result
        }

        img.resize(sizeIcon, sizeIcon)

        // Append to the image list
        var nimage = Image.create(sizeIcon * (index + 1), sizeIcon, .BGRA8)
        if curImg.isValid()
        {
            nimage.mix(curImg, 0, 0)
        }

        nimage.mix(img, sizeIcon * index, 0)
        let uploaded = .renderer.addImage(nimage)
        if not uploaded.isValid()
        {
            return result
        }

        curImgList.release(.renderer)
        curImg[] = #move nimage
        curImgList.set(uploaded, sizeIcon, sizeIcon)
        if small
        {
            .mapFileSmallIcons.add(name, index)
        }
        else
        {
            .mapFileBigIcons.add(name, index)
        }

        return Icon.from(curImgList, index)
    }

    internal mtd specialDirectoryIcon(what: Env.SpecialDirectory, small = true)->Icon
    {
        var val  = what
        let name = Reflection.enumName(Env.SpecialDirectory, &val).toString()

        if small
        {
            let here = .mapFileSmallIcons.tryFind(name)
            if here
            {
                return Icon.from(&.fileSmallIconsImageList, here.value)
            }
        }
        else
        {
            let here = .mapFileBigIcons.tryFind(name)
            if here
            {
                return Icon.from(&.fileBigIconsImageList, here.value)
            }
        }

        var sgi: SHSTOCKICONINFO
        sgi.cbSize = #sizeof(SHSTOCKICONINFO)

        var whatWin = SHSTOCKICONID.SIID_FOLDER
        switch what
        {
        case .Desktop:        whatWin = .SIID_DESKTOPPC
        case .UserVideos:     whatWin = .SIID_VIDEOFILES
        case .UserPictures:   whatWin = .SIID_IMAGEFILES
        case .UserMusic:      whatWin = .SIID_AUDIOFILES
        case .CommonVideos:   whatWin = .SIID_VIDEOFILES
        case .CommonPictures: whatWin = .SIID_IMAGEFILES
        case .CommonMusic:    whatWin = .SIID_AUDIOFILES
        default:              break
        }

        catch SHGetStockIconInfo(whatWin, SHGSI_ICON | (small ? SHGSI_SMALLICON : SHGSI_LARGEICON), &sgi)
        if not sgi.hIcon
        {
            return {}
        }

        return .addIconToImageList(name, sgi.hIcon, small)
    }

    internal mtd fileOrDirectoryIcon(name: string, isDirectory: bool, small = true)->Icon
    {
        var result: #returntype
        if not name.count
        {
            return result
        }

        var ext = Path.extension(name)

        var extractFromFile = false
        if isDirectory and name[name.count - 1] == Path.VolumeSeparator
        {
            ext = "c:"
        }
        else if isDirectory
        {
            ext = "c:/temp"
        }
        else if ext == ".exe" or ext == ".dll"
        {
            extractFromFile = true
            ext = name
        }
        else if ext == null
        {
            ext = ".txt"
        }

        if small
        {
            let here = .mapFileSmallIcons.tryFind(ext)
            if here
            {
                return Icon.from(&.fileSmallIconsImageList, here.value)
            }
        }
        else
        {
            let here = .mapFileBigIcons.tryFind(ext)
            if here
            {
                return Icon.from(&.fileBigIconsImageList, here.value)
            }
        }

        var sfi: SHFILEINFOA
        if extractFromFile
        {
            catch ExtractIconExA(ext.buffer, 0, null, &sfi.hIcon, 1)
            if not sfi.hIcon
            {
                ext = Path.extension(name)
                if ext == null
                {
                    ext = ".txt"
                }

                if small
                {
                    let here = .mapFileSmallIcons.tryFind(ext)
                    if here
                    {
                        return Icon.from(&.fileSmallIconsImageList, here.value)
                    }
                }
                else
                {
                    let here = .mapFileBigIcons.tryFind(ext)
                    if here
                    {
                        return Icon.from(&.fileBigIconsImageList, here.value)
                    }
                }
            }
        }

        let safeExt = ext orelse ".txt"
        if not sfi.hIcon
        {
            discard SHGetFileInfoA(safeExt.buffer, isDirectory ? FILE_ATTRIBUTE_DIRECTORY : FILE_ATTRIBUTE_NORMAL, &sfi, #sizeof(SHFILEINFOA), SHGFI_USEFILEATTRIBUTES | SHGFI_ICON | SHGFI_SMALLICON)
        }

        if not sfi.hIcon
        {
            return result
        }

        return .addIconToImageList(safeExt, sfi.hIcon, small)
    }
}
