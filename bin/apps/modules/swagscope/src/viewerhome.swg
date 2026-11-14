#global internal

using Core, Pixel, Gui

// One file of the history the home shows: the first one as the card to take up again, the others
// as tiles.
struct ViewerHomeRow
{
    file:      String
    opened:    u64         // Local ticks of the last time it was opened; zero when unknown.
    glyph:     Icon        // Glyph of the file's kind, standing in for the picture until it arrives.
    texture:   Texture     // Preview of the file, rendered in the background; invalid until then.
    attempted: bool        // Whether its preview was asked for, whatever came of it.

    // Only a viewer that decodes a picture of its file, or a text a reader can recognise, gives
    // the home a preview; a sample of the bytes of anything else says nothing about the file, so
    // its glyph stays. A picture fills its frame; a page of text stands whole inside it.
    previewable: bool
    fit = FileTile.Fit.Cover
}

// One folder the home offers to explore: one the reader explored lately, or, on a first launch,
// one of the system's own places.
struct ViewerHomePlace
{
    folder: String
    glyph:  Icon
}

// Where the parts of the home stand, from the size of the window.
struct ViewerHomeLayout
{
    column:      Math.Rectangle     // The measured column every part shares an edge with.
    mark:        Math.Rectangle     // The Scope mark of a home without history.
    line:        f32                // Middle of the invitation beside the direct actions.
    actions:     f32                // Top of the direct actions.
    heroLabel:   Math.Rectangle     // Section label of the card.
    hero:        Math.Rectangle     // Picture of the card.
    heroText:    Math.Rectangle     // Words of the card, beside its picture.
    recentLabel: Math.Rectangle     // Section label of the tiles.
    tile:        Math.Point         // Size of the picture of one tile.
    tilesTop:    f32
    columns:     u64 = 1
    placesLabel: Math.Rectangle     // Section label of the folders.
    placesTop:   f32
    placesLeft:  f32                // Left of the ground of the first chip.
    showPlaces:  bool               // Whether the folders have room above the hint line.
}

// The window without a file.
//
// With a history it is a page of what was read lately: the last file as a card with its picture,
// where it was left and the one action that takes it up again; the files before it as tiles with
// their pictures; and the folders explored lately. The invitation to drop and the direct actions
// remain between the last file and the recent ones. Without history, the Scope mark joins those
// actions and the system's places. Everything older is in the lens, under `/`.
//
// The tile under the pointer is ringed and offers the cross that takes it out of the history; the
// Clear menu at the end of the label of the tiles offers the partial clears and, apart, the whole
// one.
struct ViewerHome
{
    using wnd: Wnd

    late window:        *ViewerWindow
    late clearButton:   *IconButton
    late removeButton:  *IconButton
    late resumeButton:  *PushButton
    late restartButton: *PushButton
    late openButton:    *PushButton
    late exploreButton: *PushButton

    message:      String     // Sentence standing in for the invitation, such as why a file did not open.
    rows:         Array'ViewerHomeRow
    places:       Array'ViewerHomePlace
    explored:     bool       // Whether `places` are folders the reader explored, rather than the system's.
    hovered:      u64 = Swag.U64.Max
    hoveredPlace: u64 = Swag.U64.Max
    chosen:       u64 = Swag.U64.Max
    pointerIn:    bool
    now:          u64        // Local ticks the times are written against; zero for the clock.
    preview:      ExplorerPreview
    previewRow:   u64 = Swag.U64.Max
}

impl ViewerHome
{
    // The measures of the home, from its picture.
    const ColumnWidth   = 880.0
    const ColumnMargin  = 48.0
    const HeroHeight    = 150.0
    const HeroWidth     = 240.0     // A 16:10 picture: a film frame, a page, a photograph.
    const HeroGap       = 28.0
    const LabelHeight   = 20.0
    const LabelGap      = 12.0
    const SectionGap    = 36.0
    const TileGap       = 20.0
    const TileMinWidth  = 120.0
    const MaxTiles      = 5'u64
    const MaxRows       = 1 + MaxTiles
    const PlaceHeight   = 32.0
    const PlaceInset    = 12.0
    const PlaceGap      = 6.0
    const PlaceGlyph    = 16.0
    const MaxPlaces     = 6'u64
    const BottomReserve = 64.0      // The foot of the window, where the hint line stands.
    const MarkSize      = 64.0
    const MarkToLine    = 34.0
    const LineToActions = 28.0
    const ActionInset   = 10.0
    const ActionsGap    = 8.0
    const TitleSize     = 22'u32
    const FontSize      = 14'u32
    const MonoSize      = 12'u32

    func create(parent: *Wnd, window: *ViewerWindow)->*ViewerHome
    {
        with let result = Wnd.create'ViewerHome(parent, "scope.home")
        {
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
            .focusPolicy     = .Click
            .window          = window
        }

        let texts = appStrings()
        with result.clearButton = IconButton.createQuiet(result)
        {
            .setQuietText(texts.home_Clear)
            .sigPressed += func|home = result|(_) { home.showClearMenu() }
            .hide()
        }

        with result.removeButton = IconButton.create(result,
                                                     result.theme().icon(.Remove, themeRowIconSize(result.themeMetrics())),
                                                     Math.Rectangle{0, 0,
                                                                    result.themeMetrics().control_InspectorHeight,
                                                                    result.themeMetrics().control_InspectorHeight},
                                                     "scope.home.remove")
        {
            .toolTip = texts.home_RemoveRecent
            .sigPressed += func|home = result|(_) { home.confirmRemoveHovered() }
            .hide()
        }

        with result.resumeButton = PushButton.create(result, texts.home_Open, {}, "scope.home.resume", .Strong)
        {
            .sigPressed += func|home = result|(_) { home.openRow(0) }
            .hide()
        }

        with result.restartButton = PushButton.create(result, texts.home_StartOver, {}, "scope.home.restart", .Flat)
        {
            .sigPressed += func|home = result|(_) { home.restartRow(0) }
            .hide()
        }

        with result.openButton = PushButton.create(result, texts.home_OpenFile, {}, ViewerCommands.Open)
        {
            .toolTip = Input.formatKeyShortcut(.Control, .O)
            .hide()
        }

        with result.exploreButton = PushButton.create(result, texts.cmd_Explore, {}, ViewerCommands.Explore)
        {
            .toolTip = Input.formatKeyShortcut(.Control, .E)
            .hide()
        }

        return result
    }

    // Shows `message` in place of the invitation, or the invitation with an empty one.
    mtd setMessage(message: string)
    {
        .message = message
        .invalidate()
    }

    // Takes the last files read and the folders explored from the window's history again, keeping
    // the pictures of the files still shown.
    mtd refresh()
    {
        let window = .window
        var rows: Array'ViewerHomeRow
        for index in Math.min(window.recent.count, MaxRows)
        {
            let file     = window.recent[index].toString()
            with let row = rows.emplaceInitAddress()
            {
                .file   = file
                .opened = index < window.recentOpened.count ? window.recentOpened[index] : 0
                .glyph  = me.theme().fileGlyph(file, false, 32)
            }

            var plugin: u64
            if window.index.namePlugin(file, &plugin)
            {
                let descriptor  = &window.index.plugins[plugin]
                row.previewable = descriptor.thumbnail != null or descriptor.textual
                row.fit = descriptor.thumbnail != null and (descriptor.key == "image" or descriptor.key == "video") ? .Cover : .Contain
            }

            for &old in .rows where old.file == file
            {
                row.texture   = old.texture
                row.attempted = old.attempted
                old.texture   = {}
            }
        }

        for &old in .rows where old.texture.isValid() do
            .app().renderer.removeTexture(&old.texture)
        .rows = #move rows
        .refreshPlaces()

        if .hovered >= .rows.count do
            .hovered = Swag.U64.Max
        if .hoveredPlace >= .places.count do
            .hoveredPlace = Swag.U64.Max
        if .chosen >= .rows.count do
            .chosen = .rows.isEmpty() ? Swag.U64.Max : 0
        .refreshButtons()
        .layoutChildren()
        .removeButton.hide()
        .requestPreview()
        .invalidate()
    }

    // The folders explored lately, or the system's places when there are none.
    private mtd refreshPlaces()
    {
        .places.clear()
        for folder in .window.exploredFolders where Directory.exists(folder[])
        {
            if .places.count == MaxPlaces do
                break
            .places.add(ViewerHomePlace{folder[], .theme().fileGlyph(folder[], true)})
        }
        .explored = not .places.isEmpty()
        if .explored do
            return

        for folder in .window.systemPlaces where Directory.exists(folder[])
        {
            if .places.count == MaxPlaces do
                break
            .places.add(ViewerHomePlace{folder[], .theme().fileGlyph(folder[], true)})
        }
    }

    // Names the card's action by what it does: where it takes the file up again, or only Open.
    private mtd refreshButtons()
    {
        let texts = appStrings()
        let point = .rows.isEmpty() ? null : .window.resumePoint(.rows[0].file)
        .resumeButton.setText(point ? point.positionText() : String.from(texts.home_Open))
        .resumeButton.fitWidthToLabel(96)
        .restartButton.setText(texts.home_StartOver)
        .restartButton.fitWidthToLabel()
        .openButton.setText(texts.home_OpenFile)
        .openButton.fitWidthToLabel(120)
        .exploreButton.setText(texts.cmd_Explore)
        .exploreButton.fitWidthToLabel(120)
        .clearButton.setQuietText(texts.home_Clear)

        let history = not .rows.isEmpty()
        .resumeButton.show(history)
        .restartButton.show(point != null)
        .clearButton.show(history)
        .openButton.show()
        .exploreButton.show()
    }

    // Returns where every part of the home stands, from the size of the home.
    mtd layout()->ViewerHomeLayout
    {
        var result: #returntype
        let client  = .clientRect()
        let metrics = .themeMetrics()
        let width   = Math.min(ColumnWidth, Math.max(client.width - 2 * ColumnMargin, 0))
        let left    = Math.round(client.horzCenter() - width * 0.5)
        let ceiling = client.y + .stripInset() + 24
        let room    = client.bottom() - BottomReserve - ceiling
        var places  = .places.isEmpty() ? 0 : SectionGap + LabelHeight + LabelGap + PlaceHeight

        // The folders are the first to give way when the window is too short for the whole page.
        func fit(height: *f32, places: *f32, room: f32)->bool
        {
            if height[] > room and places[] > 0
            {
                height[] -= places[]
                places[] = 0
            }

            return places[] > 0
        }

        if .rows.isEmpty()
        {
            var height = MarkSize + MarkToLine + LineToActions + metrics.btnPush_Height + places
            result.showPlaces = fit(&height, &places, room)
            let top = Math.round(Math.max(ceiling, client.y + (client.height - height) * 0.42))
            result.column      = {left, top, width, height}
            result.mark        = {Math.round(client.horzCenter() - MarkSize * 0.5), top, MarkSize, MarkSize}
            result.line        = top + MarkSize + MarkToLine
            result.actions     = result.line + LineToActions
            result.placesLeft  = Math.round(client.horzCenter() - .placesWidth(width) * 0.5)
            result.placesLabel = {result.placesLeft + PlaceInset, result.actions + metrics.btnPush_Height + SectionGap, width, LabelHeight}
            result.placesTop   = result.placesLabel.bottom() + LabelGap
            return result
        }

        result.columns = Math.clamp(cast(u64, (width + TileGap) / (TileMinWidth + TileGap)), 1, MaxTiles)
        let tileWidth  = Math.floor((width - cast(f32, result.columns - 1) * TileGap) / cast(f32, result.columns))
        result.tile    = {tileWidth, Math.round(tileWidth * 0.75)}
        let tiles      = .rows.count - 1
        let tileRows   = (tiles + result.columns - 1) / result.columns
        let tilesSpan  = tiles ? cast(f32, tileRows) * (result.tile.y + FileTile.captionHeight(me)) + cast(f32, tileRows - 1) * TileGap : 0
        let actionSpan = metrics.btnPush_Height + 2 * ActionInset
        let recent     = tiles ? LabelHeight + LabelGap + tilesSpan : 0
        var height     = LabelHeight + LabelGap + HeroHeight + actionSpan + recent + places
        result.showPlaces = fit(&height, &places, room)
        let top = Math.round(Math.max(ceiling, client.y + (client.height - height) * 0.42))

        result.column    = {left, top, width, height}
        result.heroLabel = {left, top, width, LabelHeight}
        result.hero      = {left, top + LabelHeight + LabelGap, HeroWidth, HeroHeight}
        result.heroText  = {result.hero.right() + HeroGap, result.hero.y, Math.max(width - HeroWidth - HeroGap, 0), HeroHeight}
        result.actions   = result.hero.bottom() + ActionInset
        result.line      = result.actions + metrics.btnPush_Height * 0.5
        var bottom       = result.hero.bottom() + actionSpan
        if tiles
        {
            result.recentLabel = {left, bottom, width, LabelHeight}
            result.tilesTop    = result.recentLabel.bottom() + LabelGap
            bottom             = result.tilesTop + tilesSpan
        }

        result.placesLeft  = left - PlaceInset
        result.placesLabel = {left, bottom + SectionGap, width, LabelHeight}
        result.placesTop   = result.placesLabel.bottom() + LabelGap
        return result
    }

    // Returns the ground of chip `index`, without asking where the line of chips starts.
    private mtd placeWidth(index: u64)->f32 => Math.round(PlaceInset * 2 + PlaceGlyph + 8 + Painter.measureString(.placeName(index), .theme().createDefaultFont(FontSize)).width)

    // Returns the width of the chips that fit in `room`, the gaps between them included.
    private mtd placesWidth(room: f32)->f32
    {
        var result = 0.0
        for i in .places.count
        {
            let next = result + (i ? PlaceGap : 0) + .placeWidth(i)
            if next > room + PlaceInset * 2 do
                break
            result = next
        }

        return result
    }

    // Returns the picture of row `index`: the card's for the first one, a tile's for the others.
    mtd pictureRect(index: u64)->Math.Rectangle
    {
        let place = .layout()
        if index == 0 do
            return place.hero
        let tile = index - 1
        return {place.column.x + cast(f32, tile % place.columns) * (place.tile.x + TileGap),
                place.tilesTop + cast(f32, tile / place.columns) * (place.tile.y + FileTile.captionHeight(me) + TileGap),
                place.tile.x, place.tile.y}
    }

    // Returns what the pointer can take of row `index`: the whole card, or a tile with its caption.
    mtd rowRect(index: u64)->Math.Rectangle
    {
        let picture = .pictureRect(index)
        if index == 0
        {
            let text = .layout().heroText
            return {picture.x, picture.y, text.right() - picture.x, picture.height}
        }

        return {picture.x, picture.y, picture.width, picture.height + FileTile.captionHeight(me)}
    }

    // Returns the place of the cross that takes row `index` out of the history, in the corner of its picture.
    mtd removeRect(index: u64)->Math.Rectangle
    {
        let picture = .pictureRect(index)
        let size    = .themeMetrics().control_InspectorHeight
        return {picture.right() - size - 4, picture.y + 4, size, size}
    }

    // Returns the ground of the chip of folder `index`. The chips follow one another along one
    // line, the glyph of the first one on the edge the labels share.
    mtd placeRect(index: u64)->Math.Rectangle
    {
        let place = .layout()
        var x     = place.placesLeft
        for i in Math.min(index + 1, .places.count)
        {
            let width = .placeWidth(i)
            if i == index do
                return {x, place.placesTop, width, PlaceHeight}
            x += width + PlaceGap
        }

        return {}
    }

    // Reports whether folder `index` has room on the line of the chips, and the line on the page.
    mtd placeShown(index: u64)->bool
    {
        let place = .layout()
        return place.showPlaces and index < .places.count and .placeRect(index).right() <= place.column.right() + PlaceInset
    }

    // Names folder `index` as the reader recognises it: its own name, or a drive by itself.
    mtd placeName(index: u64)->string
    {
        let folder = .places[index].folder.toString()
        let name   = Path.fileName(folder) orelse ""
        return name.count ? name : folder
    }

    private mtd layoutChildren()
    {
        // The home lays out while it is being created, before its controls exist.
        if .exploreButton == null do
            return
        let place  = .layout()
        let height = .themeMetrics().btnPush_Height
        if .rows.isEmpty()
        {
            let width = .openButton.position.width + ActionsGap + .exploreButton.position.width
            let left  = Math.round(.clientRect().horzCenter() - width * 0.5)
            .openButton.setPosition({left, place.actions, .openButton.position.width, height})
            .exploreButton.setPosition({left + .openButton.position.width + ActionsGap, place.actions, .exploreButton.position.width, height})
            return
        }

        let actionsWidth = .openButton.position.width + ActionsGap + .exploreButton.position.width
        let actionsLeft  = place.column.right() - actionsWidth
        .openButton.setPosition({actionsLeft, place.actions, .openButton.position.width, height})
        .exploreButton.setPosition({.openButton.position.right() + ActionsGap, place.actions, .exploreButton.position.width, height})

        let bottom = place.heroText.bottom() - height
        .resumeButton.setPosition({place.heroText.x, bottom, .resumeButton.position.width, height})
        .restartButton.setPosition({.resumeButton.position.right() + ActionsGap, bottom, .restartButton.position.width, height})

        let label = .rows.count > 1 ? place.recentLabel : place.heroLabel
        let width = .clearButton.position.width
        let quiet = .themeMetrics().quiet_Height
        .clearButton.setPosition({label.right() - width, label.vertCenter() - quiet * 0.5, width, quiet})
    }

    private mtd layoutRemoveButton()
    {
        if .removeButton == null do
            return
        if .hovered >= .rows.count
        {
            .removeButton.hide()
            return
        }

        .removeButton.setPosition(.removeRect(.hovered))
        .removeButton.show()
    }

    // Asks for the picture of the first row that has none yet, one at a time, in the background.
    mtd requestPreview()
    {
        if .preview.started or .window.thumbnailMode or not .isVisible() do
            return
        for &row, index in .rows where not row.attempted
        {
            row.attempted = true
            if not row.previewable do
                continue

            .previewRow       = index
            .preview.path     = row.file
            .preview.opening  = false
            .preview.online   = false
            .preview.settings = ThumbnailSettings.capture(.window, localArtworkOnly: true)
            .preview.mediaFile.clear()
            .preview.archivePath.clear()
            .preview.start(me)
            return
        }
    }

    // Reports whether every row's picture was asked for and arrived, or failed.
    mtd previewsSettled()->bool
    {
        if .preview.started do
            return false
        for &row in .rows where not row.attempted do
            return false
        return true
    }

    // Writes when a file was opened: the time today, "yesterday", the day within the week, and
    // the date before that.
    func openedText(opened, now: u64)->String
    {
        if not opened do
            return {}
        let when  = Time.Timestamp.fromTicks(opened).toDateTime()
        let today = now / Time.TicksPerDay
        let day   = opened / Time.TicksPerDay
        if day == today do
            return Format.toString("%{02}:%{02}", when.hour, when.minute)
        if day + 1 == today do
            return appStrings().home_Yesterday
        if day + 7 > today
        {
            var names = Tokenize.split(appStrings().home_Weekdays, ' 'u8)
            let index = cast(u64, when.dayOfWeek())
            if index < names.count do
                return names[index]
        }

        return Format.toString("%-%{02}-%{02}", when.year, when.month, when.day)
    }

    // Names the folder of `file` by its last `levels` levels, as a reader recognises it.
    func folderText(file: string, levels = 3'u32)->String
    {
        var result: #returntype
        var path = Path.directoryName(file) orelse ""
        for levels
        {
            let name = Path.fileName(path) orelse ""
            if not name.count do
                break
            result = result.isEmpty() ? String.from(name) : Format.toString("% / %", name, result)
            let parent = Path.directoryName(path) orelse ""
            if parent == path do
                break
            path = parent
        }

        return result
    }

    // Opens row `index` where it was left, or from its start when it has no point.
    mtd openRow(index: u64)
    {
        if index >= .rows.count do
            return
        .chosen = index
        .window.resumeFile(String.from(.rows[index].file))
    }

    // Opens row `index` from its start, forgetting where it was left.
    mtd restartRow(index: u64)
    {
        if index >= .rows.count do
            return
        .chosen = index
        .window.restartFile(String.from(.rows[index].file))
    }

    // Takes row `index` out of the history.
    mtd removeRow(index: u64)
    {
        if index >= .rows.count do
            return
        let file = String.from(.rows[index].file)
        .window.forgetRecent(file)
    }

    // Confirms the named row before taking it out of the recent-file list.
    mtd confirmRemoveRow(index: u64)
    {
        if index >= .rows.count do
            return

        let file = String.from(.rows[index].file)
        var options: MessageDlgOptions
        options.title = appStrings().home_RemoveRecentTitle
        if MessageDlg.confirm(unwrap .window.surface,
                              Format.toString("%", Path.fileName(file) orelse file),
                              appStrings().home_AskRemoveRecent,
                              options: options) == Dialog.BtnYes do
            .window.forgetRecent(file)
    }

    private mtd confirmRemoveHovered()
    {
        .confirmRemoveRow(.hovered)
    }

    // Opens the partial clears and, apart, the whole one.
    mtd showClearMenu()
    {
        const MissingId = "scope.home.clear.missing"
        const OlderId   = "scope.home.clear.older"
        const AllId     = "scope.home.clear.all"

        let texts   = appStrings()
        let missing = .window.missingRecentCount()
        let menu    = MenuCtrl.createPopup(me, owner: me)
        menu.addItem(texts.home_ClearMissing, MissingId, .theme().icon(.Remove, themeRowIconSize(.themeMetrics())), rightName: Format.toString("%", missing), disabled: missing == 0).critical = true
        menu.addItem(texts.home_ClearOlder, OlderId, .theme().icon(.Remove, themeRowIconSize(.themeMetrics())), disabled: .window.olderRecentCount() == 0).critical = true
        menu.addSeparator()
        menu.addItem(texts.home_ClearAll, AllId, .theme().icon(.RemoveAll, themeRowIconSize(.themeMetrics()))).critical = true

        switch menu.doModal(.clearButton, autoDestroy: true) orelse ""
        {
        case MissingId: .window.removeMissingRecent()
        case OlderId:   .window.removeOlderRecent()
        case AllId:     .window.confirmClearRecent()
        }
    }

    private mtd rowAt(pos: Math.Point)->u64
    {
        for i in .rows.count where .rowRect(i).contains(pos) do
            return i
        return Swag.U64.Max
    }

    private mtd placeAt(pos: Math.Point)->u64
    {
        for i in .places.count where .placeShown(i) and .placeRect(i).contains(pos) do
            return i
        return Swag.U64.Max
    }

    // Paints the card of the last file: its picture with how far it was read along its foot, its
    // name, where it lives and when it was opened, and where it was left. Its actions stand at the
    // foot of the words.
    private mtd paintHero(painter: *Painter, place: const *ViewerHomeLayout)
    {
        let colors  = .themeColors()
        let metrics = .themeMetrics()
        let row     = &.rows[0]
        let point   = .window.resumePoint(row.file)

        var content: FileTile.Content
        content.texture = row.texture
        content.icon    = row.glyph
        var options: FileTile.Options
        options.fit         = row.fit
        options.hovered     = .hovered == 0
        options.selected    = .chosen == 0 and .hasFocus()
        options.showCaption = false
        FileTile.paint(me, painter, place.hero, &content, options)

        if point
        {
            let thread = metrics.fileTile_RingWidth + 1
            painter.fillRect(Math.Rectangle{place.hero.x, place.hero.bottom() - thread, Math.round(place.hero.width * point.progress), thread}, colors.arc)
        }

        let text  = place.heroText
        let title = .theme().createDefaultFont(TitleSize, .Bold)
        let mono  = .theme().createDefaultFontFs(MonoSize)
        let scale = .deviceScale()
        let file  = row.file.toString()
        let name  = Path.fileName(file) orelse file
        var y     = text.y + 4
        painter.drawString(text.x, y, Painter.elideString(name, title, text.width, scale), title, colors.text)
        y += title.height + 6

        var facts = ViewerHome.folderText(file)
        let when  = ViewerHome.openedText(row.opened, .now ? .now : Time.Timestamp.now().ticks)
        if not when.isEmpty() do
            facts = facts.isEmpty() ? when : Format.toString("%  ·  %", facts, when)
        painter.drawString(text.x, y, Painter.elideString(facts, mono, text.width, scale), mono, colors.faintText)
        y += mono.height + 12

        // A recording says how long it is beside where it was left; a page or a share is already
        // the words of the action.
        if point and point.length > 0 do
            painter.drawString(text.x, y, point.shortText(), mono, colors.softText)
    }

    // Paints the tile of row `index` through the shared file tile: when it was opened and, when it
    // has one, where it was left.
    private mtd paintTile(painter: *Painter, index: u64)
    {
        let row    = &.rows[index]
        let point  = .window.resumePoint(row.file)
        let file   = row.file.toString()
        let when   = ViewerHome.openedText(row.opened, .now ? .now : Time.Timestamp.now().ticks)
        let detail = point ? point.shortText() : String.from("")

        var content: FileTile.Content
        content.texture     = row.texture
        content.icon        = row.glyph
        content.name        = Path.fileName(file) orelse file
        content.facts       = when
        content.detail      = detail
        if not row.texture.isValid() do
            content.placeholder = Path.extension(file) orelse ""
        var options: FileTile.Options
        options.fit      = row.fit
        options.hovered  = index == .hovered
        options.selected = index == .chosen and .hasFocus()
        FileTile.paint(me, painter, .pictureRect(index), &content, options)
    }

    // Paints the folders as quiet chips: the glyph of a folder and its name, raised under the hand.
    private mtd paintPlaces(painter: *Painter, place: const *ViewerHomeLayout)
    {
        if not place.showPlaces do
            return
        let colors  = .themeColors()
        let metrics = .themeMetrics()
        let font    = .theme().createDefaultFont(FontSize)
        SectionLabel.paint(me, painter, place.placesLabel, .explored ? appStrings().home_Folders : appStrings().home_Places)
        for i in .places.count where .placeShown(i)
        {
            let rect = .placeRect(i)
            let hot  = i == .hoveredPlace
            if hot do
                painter.fillRoundRect(rect, metrics.corner_Control, metrics.corner_Control, colors.raised)
            var glyph = .places[i].glyph
            glyph.sizeX, glyph.sizeY = PlaceGlyph
            glyph.paint(painter, rect.x + PlaceInset, Math.round(rect.vertCenter() - PlaceGlyph * 0.5), colors.faintText)
            painter.drawString(rect.x + PlaceInset + PlaceGlyph + 8, font.opticalLineTop(rect.vertCenter()), .placeName(i), font, hot ? colors.text : colors.softText)
        }
    }

    // Paints a home without history: the mark and the invitation; the actions are children.
    private mtd paintInvitation(painter: *Painter, place: const *ViewerHomeLayout)
    {
        let colors = .themeColors()
        let body   = .theme().createDefaultFont(FontSize)
        let mark   = .app().appGlyph(MarkSize)
        if mark.isValid() do
            mark.paint(painter, place.mark.x, place.mark.y, colors.strongLine)

        let line  = .message.isEmpty() ? appStrings().home_Invite : .message.toString()
        let width = Painter.measureString(line, body).width
        painter.drawString(Math.round(.clientRect().horzCenter() - width * 0.5), body.opticalLineTop(place.line), line, body, colors.softText)
    }

    // Keeps the drop invitation visible beside the same opening controls when history exists.
    private mtd paintDropHint(painter: *Painter, place: const *ViewerHomeLayout)
    {
        let body = .theme().createDefaultFont(FontSize)
        painter.drawString(place.column.x, body.opticalLineTop(place.line), appStrings().home_Invite, body, .themeColors().softText)
    }
}

impl IWnd for ViewerHome
{
    mtd impl onLayout()
    {
        .layoutChildren()
    }

    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        .layoutChildren()
        .layoutRemoveButton()
    }

    mtd impl onStateEvent(evt: *StateEvent)
    {
        if evt.kind == .Show do
            .requestPreview()
        evt.accepted = false
    }

    mtd impl onTaskEvent(evt: *TaskEvent)
    {
        if not .preview.claim(evt)
        {
            evt.accepted = false
            return
        }

        .preview.wait()
        let index = .previewRow
        .previewRow = Swag.U64.Max
        if index < .rows.count and .rows[index].file == .preview.path and .preview.image.isValid()
        {
            let uploaded = .app().renderer.addImage(.preview.image)
            if uploaded.isValid()
            {
                if .rows[index].texture.isValid() do
                    .app().renderer.removeTexture(&.rows[index].texture)
                .rows[index].texture = uploaded
            }
        }

        .preview.image = {}
        .requestPreview()
        .invalidate()
    }

    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
        .preview.task.cancel()
        .preview.wait()
        for &row in .rows where row.texture.isValid() do
            .app().renderer.removeTexture(&row.texture)
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let place   = .layout()
        painter.setAntialiased(true)

        if .rows.isEmpty()
        {
            .paintInvitation(painter, &place)
            .paintPlaces(painter, &place)
            return
        }

        let texts = appStrings()
        let point = .window.resumePoint(.rows[0].file)
        SectionLabel.paint(me, painter, place.heroLabel, point ? texts.home_Continue : texts.home_LastOpened)
        .paintHero(painter, &place)
        .paintDropHint(painter, &place)
        if .rows.count > 1
        {
            SectionLabel.paint(me, painter, place.recentLabel, texts.ui_Recent)
            for index in 1 until .rows.count do
                .paintTile(painter, index)
        }

        // The cross stands over a picture, so it keeps a ground of its own to be read on.
        if .hovered < .rows.count
        {
            let metrics = .themeMetrics()
            painter.fillRoundRect(.removeRect(.hovered), metrics.corner_Control, metrics.corner_Control, .themeColors().surface)
        }

        .paintPlaces(painter, &place)
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let pos = .surfaceToLocal(evt.surfacePos)
        switch evt.kind
        {
        case .Enter, .Move:
            let row   = .rowAt(pos)
            let place = .placeAt(pos)
            if row != .hovered or place != .hoveredPlace or not .pointerIn
            {
                .hovered      = row
                .hoveredPlace = place
                .pointerIn    = true
                .layoutRemoveButton()
                .invalidate()
            }

            evt.accepted = false

        case .Leave:
            let row = .rowAt(pos)
            .hovered      = row
            .hoveredPlace = .placeAt(pos)
            .pointerIn    = row < .rows.count
            .layoutRemoveButton()
            .invalidate()

        case .Pressed where evt.button == .Left:
            .setFocus()
            let place = .placeAt(pos)
            if place < .places.count
            {
                .window.openExplorer(String.from(.places[place].folder))
                return
            }

            let row = .rowAt(pos)
            if row >= .rows.count do
                return
            if .removeRect(row).contains(pos)
            {
                .confirmRemoveRow(row)
                return
            }

            .openRow(row)

        default:
            evt.accepted = false
        }
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed or evt.modifiers != .None or .rows.isEmpty()
        {
            evt.accepted = false
            return
        }

        switch evt.key
        {
        case .Left, .Up:
            .chosen = .chosen == Swag.U64.Max ? 0 : (.chosen ? .chosen - 1 : 0)

        case .Right, .Down:
            .chosen = .chosen == Swag.U64.Max ? 0 : Math.min(.chosen + 1, .rows.count - 1)

        case .Return where .chosen < .rows.count:
            .openRow(.chosen)

        case .Delete where .chosen < .rows.count:
            .confirmRemoveRow(.chosen)

        default:
            evt.accepted = false
            return
        }

        .invalidate()
    }

    mtd impl onFocusEvent(evt: *FocusEvent)
    {
        .invalidate()
        evt.accepted = false
    }
}
