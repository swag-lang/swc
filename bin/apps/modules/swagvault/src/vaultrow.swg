using Core, Gui, Pixel

// One vault of the list: a state dot, its name, and a mono line saying where it is and how it is open.
//
// A locked vault stands on the window's ground with a ring for its dot, and the pointer raises its
// ground. A mounted one stands on the surface ground, the way an open thing does, with the live dot,
// and carries its own quiet actions at its right: the drive to open, and the way to close it.
// Choosing a locked vault unfolds it into the card that unlocks it; the list lays that card over
// this row, whose header reuses the same drawing.
struct VaultRow
{
    using wnd: Wnd

    late
    {
        window:  *MainWindow
        open:    *IconButton
        unmount: *PushButton
    }

    path:    String     // Container file of the vault the row shows.
    header:  bool       // Whether the row only heads the unfolded card: no ground, no actions, no input.
    hovered: bool
}

impl VaultRow
{
    // Height of a row, and the places of its dot and its two lines from its top-left corner.
    const Height       = 84'f32
    const DotX         = RowOutset + 4
    const TextX        = RowOutset + 28
    const NameY        = 32'f32
    const IdentityY    = 58'f32
    const DotY         = 42'f32
    const DotRadius    = 4'f32
    const NameFontSize = 20'u32

    // Creates a row of the list in `parent`, for `window`. A `header` row draws the head of the
    // unfolded card and nothing else.
    func create(parent: *Wnd, window: *MainWindow, header = false)->*VaultRow
    {
        with let result = Wnd.create'VaultRow(parent, Math.Rectangle{0, 0, 0, Height})
        {
            .window          = window
            .header          = header
            .backgroundStyle = .Transparent
            .focusPolicy     = header ? .None : .Tab
        }

        with result.open = createQuietLink(result, "")
        {
            .sigPressed += func|row = result|(_) { row.window.openDrive(row.path) }
        }

        with result.unmount = PushButton.create(result, appStrings().ui_Unmount)
        {
            .sigPressed += func|row = result|(_) { row.window.unmountVault(row.path) }
        }

        result.refresh()
        return result
    }

    // Shows the vault at `path` on the row.
    mtd setPath(path: string)
    {
        if .path == path do
            return
        .path = path
        .refresh()
    }

    // Says the row again from what the window knows of its vault: its words and, for a mounted
    // vault, its actions.
    mtd refresh()
    {
        let drive   = .window.mountedDrives.find(.path)
        let actions = drive != null and not .header
        .open.show(actions)
        .unmount.show(actions)
        if drive do
            .open.setText(Format.toString(appStrings().ui_OpenDrive, drive.mountLabel))
        .unmount.setText(appStrings().ui_Unmount)
        .unmount.enable(.window.operation.kind == .None)
        .arrangeActions()
        .invalidate()
    }

    // Stands the actions of a mounted vault at the right of the row, centred on its height.
    mtd arrangeActions()
    {
        let room  = .clientRect()
        let right = room.right() - RowOutset
        let gap   = .themeMetrics().dialog_BtnPadding * 2

        let unmount = .unmount.measure({}).preferred
        let open    = .open.measure({}).preferred
        .unmount.arrange(Math.Rectangle{right - unmount.x, Math.round(room.vertCenter() - unmount.y * 0.5), unmount.x, unmount.y})
        .open.arrange(Math.Rectangle{right - unmount.x - gap - open.x, Math.round(room.vertCenter() - open.y * 0.5), open.x, open.y})
    }
}

impl IWnd for VaultRow
{
    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        // A window is laid out as soon as it is made, before its actions exist.
        if .unmount == null do
            return
        .arrangeActions()
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        let metrics = .themeMetrics()
        let room    = .clientRect()
        let drive   = .window.mountedDrives.find(.path)

        painter.setParams(.Antialiased)
        if not .header
        {
            if drive do
                painter.fillRoundRect(room, metrics.corner_Floating, metrics.corner_Floating, colors.surface)
            elif .hovered do
                painter.fillRoundRect(room, metrics.corner_Floating, metrics.corner_Floating, colors.raised)
        }

        // The dot says the state before the words are read: live when the drive is there, a ring
        // when the vault is at rest.
        if drive do
            painter.fillCircle(room.x + DotX, room.y + DotY, DotRadius, colors.live)
        else do
            painter.drawCircle(room.x + DotX, room.y + DotY, DotRadius - 0.75, colors.softText, 1.5)

        // The words stop short of the actions, so a long name never runs under them.
        var textRight = room.right() - RowOutset
        if .open.isLocallyVisible() do
            textRight = .open.position.x - metrics.dialog_BtnPadding
        painter.pushClippingRect(Math.Rectangle{room.x, room.y, Math.max(0, textRight - room.x), room.height})

        let nameFont = .theme().createDefaultFont(NameFontSize, .SemiBold)
        let monoFont = .theme().createDefaultFontFs(12)
        let name     = Path.fileName(.path) orelse .path.toString()
        painter.drawString(room.x + TextX, nameFont.opticalLineTop(room.y + NameY), name, nameFont, colors.text)
        painter.drawString(room.x + TextX, monoFont.opticalLineTop(room.y + IdentityY), .window.vaultIdentity(.path), monoFont, colors.faintText)

        painter.popClippingRect()
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if .header
        {
            evt.accepted = false
            return
        }

        switch evt.kind
        {
        case .Enter:
            .hovered = true
            .invalidate()

        case .Leave:
            .hovered = false
            .invalidate()

        case .Pressed where evt.button == .Left:
            .window.chooseVault(.path)

        case .Pressed where evt.button == .Right:
            .window.chooseVault(.path)
            .window.showVaultMenu(evt.surfacePos)

        case .DoubleClick where evt.button == .Left:
            .window.openDrive(.path)

        default:
            evt.accepted = false
        }
    }

    // Enter chooses the row the keyboard is on, as a click does.
    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        evt.accepted = false
        if evt.kind == .Pressed and evt.key == .Return
        {
            .window.chooseVault(.path)
            evt.accepted = true
        }
    }
}
