#global if #os == Swag.TargetOs.Windows

using Win32, Core, Pixel, Gdi32

#foreignlib("user32")

private const SPI_GETCLIENTAREAANIMATION = 0x1042'u32

private #[Swag.Foreign("user32", callconv: Swag.CallConv.C)]
{
    func SystemParametersInfoW(uiAction, uiParam: UINT, pvParam: LPVOID, fWinIni: UINT)->BOOL
}

// Dependency-visible Windows storage embedded by [[Application]].
#[Swag.Opaque, Swag.NoDoc]
public struct ApplicationNative
{
    public
    {
        fileSmallIconsImage:     Image                       // File small icons image associated with this value.
        fileSmallIconsImageList: ImageList                   // File small icons image list associated with this value.
        mapFileSmallIcons:       HashTable'(String, s32)     // Map file small icons associated with this value.

        fileBigIconsImage:     Image                       // File big icons image associated with this value.
        fileBigIconsImageList: ImageList                   // File big icons image list associated with this value.
        mapFileBigIcons:       HashTable'(String, s32)     // Map file big icons associated with this value.

        hotKeysDisabled: bool     // Hot keys disabled associated with this value.
    }
}

impl Application
{
    internal mtd refreshSystemMotionPreference()
    {
        var animationsEnabled = TRUE
        if !SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &animationsEnabled, 0) do
            return

        let wasReduced = .isReducedMotion()
        .systemReducedMotion = !animationsEnabled
        if !wasReduced and .isReducedMotion() do
            .animator.finishDecorative()
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
        if modifiers & .Alt do
            mod |= MOD_ALT
        if modifiers & .Control do
            mod |= MOD_CONTROL
        if modifiers & .Shift do
            mod |= MOD_SHIFT
        let winKey = Input.Keyboard.keyToVirtualKey(key)

        var crc32: Hash.Crc32
        crc32.update(@mkslice(cast(const [*] u8) &mod, 4))
        crc32.update(@mkslice(cast(const [*] u8) &winKey, 4))
        return cast(s32) (crc32.value() & 0x7FFFFFFF)
    }

    // A system-wide hot key belongs to the desktop of the person running the process, and only one
    // process on the machine can hold a given one. A sandboxed run therefore takes none: the
    // shortcut still enters [[Application.hotKeys]] and [[Application.dispatchHotKey]] still routes
    // it, exactly as the fake clipboard keeps clipboard semantics without touching the system one.
    //
    // Failing instead of substituting would defeat the purpose: an application that reports an
    // unavailable shortcut in its own window would paint that report during its own tests, which is
    // the flaky picture this avoids.
    internal func registerNativeHotKey(modifiers: Input.KeyModifiers, key: Input.Key) fail
    {
        if Env.isSandboxed() do
            return

        let hotKeyId = hotKeyNativeId(modifiers, key)
        let winKey   = Input.Keyboard.keyToVirtualKey(key)

        var mod: u32
        if modifiers & .Alt do
            mod |= MOD_ALT
        if modifiers & .Control do
            mod |= MOD_CONTROL
        if modifiers & .Shift do
            mod |= MOD_SHIFT

        catch UnregisterHotKey(null, hotKeyId)
        RegisterHotKey(null, hotKeyId, mod, winKey)
    }

    // Symmetrical to [[registerNativeHotKey]]: a sandboxed run holds no system hot key to release.
    internal func unregisterNativeHotKey(modifiers: Input.KeyModifiers, key: Input.Key)
    {
        if Env.isSandboxed() do
            return

        catch UnregisterHotKey(null, hotKeyNativeId(modifiers, key))
    }

    internal mtd sendHotKey(msg: MSG)
    {
        if .hotKeysDisabled do
            return
        using Input
        var modifiers: KeyModifiers
        if msg.lParam & MOD_ALT do
            modifiers |= .Alt
        if msg.lParam & MOD_CONTROL do
            modifiers |= .Control
        if msg.lParam & MOD_SHIFT do
            modifiers |= .Shift
        let key = Keyboard.virtualKeyToKey(cast() (msg.lParam >> 16))

        .dispatchHotKey(modifiers, key)
    }

    internal mtd sendSystemEvents()
    {
        if !.renderer.needsNativeWindow() do
            return

        var msg: MSG
        while PeekMessageW(&msg, null, 0, 0, PM_REMOVE) != 0
        {
            if msg.message == WM_HOTKEY do
                .sendHotKey(msg)
            else
            {
                TranslateMessage(&msg)
                DispatchMessageW(&msg)
            }
        }
    }

    internal mtd surfaceAtNative(x, y: f32)->#null *Surface
    {
        let pt   = POINT{cast(s32) x, cast(s32) y}
        let hWnd = WindowFromPoint(pt)
        if hWnd == null do
            return null

        for s in .surfaces
        {
            if s.native.hWnd == hWnd
            {
                if .modalSurfaces.count and s != .modalSurfaces.back() do
                    return null
                return s
            }
        }

        return null
    }

    internal mtd addIconToImageList(name: string, hIcon: HICON, small: bool)->Icon
    {
        var result: retval

        var index:      s32
        var curImg:     *Image     = undefined
        var curImgList: *ImageList = undefined

        if small
        {
            index = cast(s32) .mapFileSmallIcons.count
            .mapFileSmallIcons.add(name, index)
            curImg     = &.fileSmallIconsImage
            curImgList = &.fileSmallIconsImageList
        }
        else
        {
            index = cast(s32) .mapFileBigIcons.count
            .mapFileBigIcons.add(name, index)
            curImg     = &.fileBigIconsImage
            curImgList = &.fileBigIconsImageList
        }

        let sizeIcon = small ? 16 : 32

        // Convert icon to image
        var img = catch Image.from(hIcon) as err
        defer catch DestroyIcon(hIcon)
        if err != null do
            return result
        img.resize(sizeIcon, sizeIcon)

        // Append to the image list
        var nimage = Image.create(sizeIcon * (index + 1), sizeIcon, .BGRA8)
        if curImg.isValid() do
            nimage.mix(curImg, 0, 0)
        nimage.mix(img, sizeIcon * index, 0)
        curImg[] = nimage

        curImgList.release(.renderer)
        curImgList.set(.renderer.addImage(curImg), sizeIcon, sizeIcon)

        return Icon.from(curImgList, index)
    }

    internal mtd specialDirectoryIcon(what: Env.SpecialDirectory, small = true)->Icon
    {
        var val  = what
        let name = Reflection.enumName(Env.SpecialDirectory, &val).toString()

        if small
        {
            let here = .mapFileSmallIcons.tryFind(name)
            if here do
                return Icon.from(&.fileSmallIconsImageList, here.value)
        }
        else
        {
            let here = .mapFileBigIcons.tryFind(name)
            if here do
                return Icon.from(&.fileBigIconsImageList, here.value)
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
        }

        catch SHGetStockIconInfo(whatWin, SHGSI_ICON | (small ? SHGSI_SMALLICON : SHGSI_LARGEICON), &sgi)
        if !sgi.hIcon do
            return {}
        return .addIconToImageList(name, sgi.hIcon, small)
    }

    internal mtd fileOrDirectoryIcon(name: string, isDirectory: bool, small = true)->Icon
    {
        var result: retval
        if !@countof(name) do
            return result

        var ext = Path.extension(name)

        var extractFromFile = false
        if isDirectory and name[@countof(name) - 1] == Path.VolumeSeparator do
            ext = "c:"
        elif isDirectory do
            ext = "c:/temp"
        elif ext == ".exe" or ext == ".dll"
        {
            extractFromFile = true
            ext             = name
        }
        elif ext == null do
            ext = ".txt"

        if small
        {
            let here = .mapFileSmallIcons.tryFind(ext)
            if here do
                return Icon.from(&.fileSmallIconsImageList, here.value)
        }
        else
        {
            let here = .mapFileBigIcons.tryFind(ext)
            if here do
                return Icon.from(&.fileBigIconsImageList, here.value)
        }

        var sfi: SHFILEINFOA
        if extractFromFile
        {
            catch ExtractIconExA(@dataof(ext), 0, null, &sfi.hIcon, 1)
            if !sfi.hIcon
            {
                ext = Path.extension(name)
                if ext == null do
                    ext = ".txt"
                if small
                {
                    let here = .mapFileSmallIcons.tryFind(ext)
                    if here do
                        return Icon.from(&.fileSmallIconsImageList, here.value)
                }
                else
                {
                    let here = .mapFileBigIcons.tryFind(ext)
                    if here do
                        return Icon.from(&.fileBigIconsImageList, here.value)
                }
            }
        }

        let safeExt = ext orelse ".txt"
        if !sfi.hIcon do
            discard SHGetFileInfoA(@dataof(safeExt), isDirectory ? FILE_ATTRIBUTE_DIRECTORY : FILE_ATTRIBUTE_NORMAL, &sfi, #sizeof(SHFILEINFOA), SHGFI_USEFILEATTRIBUTES | SHGFI_ICON | SHGFI_SMALLICON)
        if !sfi.hIcon do
            return result

        return .addIconToImageList(safeExt, sfi.hIcon, small)
    }
}
