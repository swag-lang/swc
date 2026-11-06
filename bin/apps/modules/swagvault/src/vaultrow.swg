using Core, Gui, Pixel

// One vault of the list: a state dot, its name, and a mono line saying where it is and how it is open.
//
// A locked vault stands on the window's ground with a ring for its dot, and a faint chevron says
// it opens; under the pointer or the keyboard its ground rises and the chevron is joined by the
// word of what choosing it does. A mounted one stands on the surface ground, the way an open thing
// does, with the live dot: its drive, set large at its right, opens it, a thread under its words
// says how full it is, and the way to close it stands last. Choosing a locked vault unfolds it into
// the card that unlocks it; the list lays that card over this row, whose header reuses the same
// drawing.
struct VaultRow
{
    using wnd: Wnd

    late
    {
        window:  *MainWindow
        open:    *IconButton
        unmount: *PushButton
    }

    path:          String     // Container file of the vault the row shows.
    header:        bool       // Whether the row only heads the unfolded card: no ground, no actions, no input.
    hovered:       bool
    focused:       bool
    containerSize: u64     // Size of the container file of a locked vault, or zero when it cannot be read.
}

impl VaultRow
{
    // Heights of a locked and of a mounted row, and the places of their parts from the row's
    // top-left corner. The lines are placed by their centres.
    const Height        = 84'f32
    const MountedHeight = 124'f32
    const DotX          = RowOutset + 4
    const TextX         = RowOutset + 28
    const NameY         = 32'f32
    const IdentityY     = 58'f32
    const DotY          = 42'f32
    const DotRadius     = 4'f32
    const NameFontSize  = 20'u32

    // The fullness of a mounted vault: a thread under its identity, and the room left under it.
    const ThreadY     = 82'f32
    const ThreadWidth = 2'f32
    const SpaceY      = 100'f32

    // The drive of a mounted vault is a large light figure; a destination too long to read as one
    // is named in the ordinary words instead.
    const DriveFontSize = 34'u32
    const DriveMaxWidth = 112'f32

    // Air between the words of a locked row and what its right edge says.
    const OpenHintGap = 8'f32

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

    // Returns the height the row takes in the list: a mounted vault has a thread more to show.
    mtd height()->f32 => .window.isMounted(.path) and not .header ? MountedHeight : Height

    // Says the row again from what the window knows of its vault: its words and, for a mounted
    // vault, its actions.
    mtd refresh()
    {
        let drive   = .window.mountedDrives.find(.path)
        let actions = drive != null and not .header
        .open.show(actions)
        .unmount.show(actions)
        if drive do
            .showDrive(drive.mountLabel)
        .unmount.setText(appStrings().ui_Unmount)
        .unmount.enable(.window.operation.kind == .None)

        // A locked container says how large it is; reading it here keeps the file system out of
        // the paint.
        .containerSize = 0
        if not drive and not .path.isEmpty() do
            .containerSize = catch File.info(.path).size

        .arrangeActions()
        .invalidate()
    }

    // Names the drive of the mounted vault as a large light figure, or in ordinary words when the
    // destination is too long to read at a glance, as a folder is.
    mtd showDrive(mountLabel: string)
    {
        let theme = .theme()
        let words = Format.toString(appStrings().ui_OpenDrive, mountLabel)
        .open.toolTip = words

        .open.style.setFont(theme.createDefaultFont(DriveFontSize, .Light), .Regular)
        .open.setText(mountLabel)
        if .open.measure({}).preferred.x <= DriveMaxWidth do
            return

        .open.style.setFont(theme.createDefaultFont(theme.metrics.defaultFontSize), .Regular)
        .open.setText(words)
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

    // Draws the right edge of a locked row: a faint chevron at rest, joined by the word of what
    // choosing the vault does while the pointer or the keyboard is on it. Returns where the words
    // of the row must stop, the widest the edge can take, so they never move under the hand.
    mtd paintOpenHint(painter: *Painter, room: Math.Rectangle)->f32
    {
        let colors  = .themeColors()
        let metrics = .themeMetrics()
        let font    = .theme().createDefaultFont(metrics.defaultFontSize)
        let chevron = .theme().icon(.ChevronRight, themeRowIconSize(metrics))
        let word    = appStrings().ui_Unlock
        let wordW   = Painter.measureString(word, font).width

        // The word is centred on its capitals, and the chevron on the same point.
        let centerY  = room.vertCenter()
        let chevronX = room.right() - RowOutset - chevron.sizeX
        let wordX    = chevronX - metrics.iconText_Margin - wordW
        let active   = .hovered or .focused
        if active do
            painter.drawString(wordX, font.opticalLineTop(centerY), word, font, colors.softText)
        chevron.paint(painter, chevronX, Math.round(centerY - chevron.sizeY * 0.5), active ? colors.softText : colors.faintText)

        return wordX - OpenHintGap
    }

    // Draws how full a mounted vault is: an Arc thread across the room of its words, the used
    // part filled, and under it the room left of the whole.
    mtd paintSpace(painter: *Painter, room: Math.Rectangle, textRight: f32, drive: *MountedDrive)
    {
        if not drive.totalBytes do
            return

        let colors = .themeColors()
        let left   = room.x + TextX
        let width  = Math.max(0, textRight - left)
        let used   = drive.totalBytes - Math.min(drive.availableBytes, drive.totalBytes)
        let filled = Math.round(width * cast(f32, cast(f64, used) / cast(f64, drive.totalBytes)))

        let thread = Math.Rectangle{left, room.y + ThreadY, width, ThreadWidth}
        painter.fillRoundRect(thread, ThreadWidth * 0.5, ThreadWidth * 0.5, colors.raised)
        if filled > 0 do
            painter.fillRoundRect(Math.Rectangle{left, thread.y, filled, ThreadWidth}, ThreadWidth * 0.5, ThreadWidth * 0.5, colors.arc)

        let monoFont = .theme().createDefaultFontFs(12)
        let space    = Format.toString(appStrings().ui_DriveFree, capacityText(drive.availableBytes), capacityText(drive.totalBytes))
        painter.drawString(left, monoFont.opticalLineTop(room.y + SpaceY), space, monoFont, colors.faintText)
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
            elif .hovered or .focused do
                painter.fillRoundRect(room, metrics.corner_Floating, metrics.corner_Floating, colors.raised)
        }

        // The dot says the state before the words are read: live when the drive is there, a ring
        // when the vault is at rest.
        if drive do
            painter.fillCircle(room.x + DotX, room.y + DotY, DotRadius, colors.live)
        else do
            painter.drawCircle(room.x + DotX, room.y + DotY, DotRadius - 0.75, colors.softText, 1.5)

        // The words stop short of what the right edge holds, so a long name never runs under it.
        var textRight = room.right() - RowOutset
        if .open.isLocallyVisible() do
            textRight = .open.position.x - metrics.dialog_BtnPadding
        elif not .header do
            textRight = .paintOpenHint(painter, room)

        if drive and not .header do
            .paintSpace(painter, room, textRight, drive)

        painter.pushClippingRect(Math.Rectangle{room.x, room.y, Math.max(0, textRight - room.x), room.height})

        let nameFont = .theme().createDefaultFont(NameFontSize, .SemiBold)
        let monoFont = .theme().createDefaultFontFs(12)
        let name     = Path.fileName(.path) orelse .path.toString()
        let identity = .window.vaultPlace(.path, .containerSize)
        painter.drawString(room.x + TextX, nameFont.opticalLineTop(room.y + NameY), name, nameFont, colors.text)
        painter.drawString(room.x + TextX, monoFont.opticalLineTop(room.y + IdentityY), identity, monoFont, colors.faintText)

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

    // The row the keyboard is on rises and names what Enter does, as the pointer makes it.
    mtd impl onFocusEvent(evt: *FocusEvent)
    {
        .focused = evt.kind == .Gained
        .invalidate()
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
