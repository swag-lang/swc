impl MainWnd
{
    // Builds the menu bar in the caption: the File, Capture, Edit, Image, View, and Help menus.
    mtd createTopMenu()
    {
        Swag.assert(me.parent != null)
        let parentWnd = me.parent
        let metrics   = .themeMetrics()
        with .topMenu = MenuCtrl.createBar(me, owner: me)
        {
            .sendToBack()
            .dockStyle       = .Top
            .backgroundStyle = .Transparent

            // The bar rides inside the strip, which carries the application mark on its
            // leading edge: the first menu starts past the mark instead of over it.
            .padding.x = metrics.wnd_CaptionMarginTitle + metrics.wnd_CaptionIconSize + metrics.menuBar_SpaceBetween * 0.5
        }

        .fitTopMenuToStrip()

        // File menu
        with let fileMenu = MenuCtrl.createPopup(parentWnd, owner: me)
        {
            .addGroup([ActionFile.NewImage, ActionFile.NewFromClipboard])
            .addGroup([ActionFile.OpenImage, ActionFile.SaveAsImage])
            .addGroup([ActionFile.SaveAsLinkedImage, ActionFile.UpdateLinkedImage, ActionFile.UnlinkImage])
            .addGroup([ActionFile.FileDetails])
            .addItems([ActionGlobal.Minimize, ActionGlobal.Exit])
            topMenu.addPopup(func()->string => appStrings().ui_MenuFile, fileMenu)
        }

        // Capture menu
        with let captureMenu = MenuCtrl.createPopup(parentWnd, owner: me)
        {
            .addItems([ActionCapture.Area, ActionCapture.LastArea, ActionCapture.FullScreen, ActionCapture.ActiveWnd])

            for idx in me.monitors.count do
                .addItem(ActionCapture.screenId(idx))

            .addSeparator()
            .addItem(ActionCapture.HideEditor)
            .addItem(ActionCapture.CaptureCursor)

            with let delayMenu = MenuCtrl.createPopup(captureMenu, owner: me)
            {
                .addGroup([ActionCaptureDelay.Delay0])
                .addItems([ActionCaptureDelay.Delay1, ActionCaptureDelay.Delay2, ActionCaptureDelay.Delay5, ActionCaptureDelay.Delay9])
                captureMenu.addPopup(delayMenu, ActionCaptureDelay.Delay)
            }

            topMenu.addPopup(func()->string => appStrings().ui_MenuCapture, captureMenu)

            .addSeparator()
            .addItems([ActionCapture.ToInPlace, ActionCapture.ToEditor, ActionCapture.ToClipboard])
        }

        // Edit menu
        with let editMenu = MenuCtrl.createPopup(parentWnd, owner: me)
        {
            .addGroup([ActionUndo.DoUndo, ActionUndo.DoRedo])
            .addGroup([ActionCopyPaste.Copy, ActionCopyPaste.Cut, ActionCopyPaste.Paste])
            .addGroup([ActionSelection.SelectAll, ActionSelection.SelectSameAll, ActionSelection.DeSelectAll, ActionSelection.InvertSelection])
            .addGroup([ActionGroup.Group, ActionGroup.Ungroup])
            .addGroup([ActionEdit.ResetRotation])
            .addGroup([ActionSelection.Freeze])
            .addItems([ActionSelection.Snap])
            topMenu.addPopup(func()->string => appStrings().ui_MenuEdit, editMenu)
        }

        // Image menu
        with let imageMenu = MenuCtrl.createPopup(parentWnd, owner: me)
        {
            .addGroup([ActionCopyPaste.CopyAsImage])
            .addGroup([ActionImage.RestoreOrg])
            .addGroup([ActionImage.ResizeImage, ActionImage.ExpandImage, ActionImage.ExpandCapture, ActionImage.TrimCapture])
            .addGroup([ActionFlatten.FlattenAll])
            .addItems([ActionImage.FlipImage, ActionImage.MirrorImage, ActionImage.RotateImageRight, ActionImage.RotateImageLeft])
            topMenu.addPopup(func()->string => appStrings().ui_MenuImage, imageMenu)
        }

        // View menu. The recent-preview size is chosen here rather than by three radio
        // buttons standing permanently beside the recent bar.
        with let viewMenu = MenuCtrl.createPopup(parentWnd, owner: me)
        {
            .addGroup([ActionZoom.ZoomIn, ActionZoom.ZoomOut])
            .addGroup([ActionZoom.Zoom1, ActionZoom.ZoomFit])
            .addGroup([ActionRecentSize.RecentSmall, ActionRecentSize.RecentMedium, ActionRecentSize.RecentBig])
            .addItems([ActionView.Clip])
            topMenu.addPopup(func()->string => appStrings().ui_MenuView, viewMenu)
        }
    }

    // Gives the menu bar the height of the strip it rides in, so its entries sit on the line of
    // the title; without a strip it keeps the height of an ordinary menu bar.
    mtd fitTopMenuToStrip()
    {
        let height = Math.max(.stripInset(), .themeMetrics().menuBar_Height)
        .topMenu.position.height = height
        .topMenu.preferredSize.y = height
    }

    // Speech-bubble glyph drawn for the Callout toolbar button: the icon sheet has no
    // sprite for this tool, so it paints its own rounded body plus a small tail. Its round
    // corners are deliberate — the glyph depicts a shape the user draws, not chrome.
    func drawCalloutGlyph(btn: *IconButton, bc: *PaintContext, pos: Math.Rectangle, _: PaintItemFlags)
    {
        bc.painter.setParams(.Antialiased)
        let col = btn.isChecked ? btn.themeColors().btnIcon_CheckedIcon : btn.themeColors().btnIcon_Icon

        // A custom painter is handed the whole content rectangle, not the icon extent, so
        // the glyph places itself where a sprite of the set would have landed: centered
        // when the cell shows no label, against the leading edge when it does.
        let glyphSize = themeActionIconSize(btn.themeMetrics())
        var box       = Math.Rectangle{pos.x, pos.vertCenter() - glyphSize * 0.5, glyphSize, glyphSize}
        if btn.flags.has(.IconOnly) or btn.name.isEmpty() do
            box.x = pos.horzCenter() - glyphSize * 0.5

        // The sprites of the set stand on roughly three fifths of their box; the bubble
        // matches that weight so the rail reads as one column of glyphs.
        var body = box
        body.inflate(-box.width * 0.20, -box.height * 0.20)
        body.height *= 0.70

        let tx = body.x + body.width * 0.28
        var tail: LinePath
        tail.start(tx, body.bottom() - 1)
        tail.lineTo(tx + body.width * 0.30, body.bottom() - 1)
        tail.lineTo(tx, body.bottom() + box.height * 0.20)
        tail.close()
        bc.painter.fillPolygon(&tail, col)

        bc.painter.fillRoundRect(body, 3, 3, col)
    }

    // The tools stand in a column against the window's left edge, one square cell each,
    // glyph only. A horizontal ribbon of labelled tiles across the top costs a whole row
    // of height, pushes the canvas down, and sends the eye across the window to change
    // tool; the rail sits where the pointer already is.
    mtd createToolRail()
    {
        let metrics     = .themeMetrics()
        let cellSize    = themeActionButtonSize(metrics)
        let glyphSize   = themeActionIconSize(metrics)
        let cellPadding = (cellSize - glyphSize) * 0.5
        with me.toolRail = StackLayoutCtrl.create(me, .Top, Math.Rectangle{0, 0, cellSize, 0})
        {
            .dockStyle       = .Left
            .spacing         = 0
            .backgroundStyle = .Window
        }

        let toolButtons = [
            ActionToolMode.Favorites, ActionToolMode.Selection, ActionToolMode.Shape,
            ActionToolMode.Arrow, ActionToolMode.Line, ActionToolMode.Poly,
            ActionToolMode.Text, ActionToolMode.Callout, ActionToolMode.Draw, ActionToolMode.Highlight,
            ActionToolMode.Step, ActionToolMode.Img, ActionToolMode.PixSel]

        for id in toolButtons
        {
            with let b = IconButton.create(me.toolRail, {}, position: Math.Rectangle{0, 0, cellSize, cellSize})
            {
                .id = id

                // Air on both sides of the glyph, so the column is separated from the window
                // edge and from the canvas by space rather than by a line.
                .setAllPaddings(Math.Vector4{cellPadding, 0, cellPadding, 0})
                if id == ActionToolMode.Callout
                {
                    .iconPainter = func(btn, bc, pos, flags) { drawCalloutGlyph(btn, bc, pos, flags) }
                    .setIconSize(glyphSize, glyphSize)
                }

                // A vertical tool rail keeps the leading rule, which reads beside the glyph rather
                // than as part of it; the glyph of the tool in use takes the color of the rule.
                .style.addStyleSheetColors("""btnIcon_CheckedBk           $btnIcon_HotBk
                                              btnIcon_CheckedText         $btnIcon_Text
                                              btnIcon_CheckedHotText      $btnIcon_Text
                                              btnIcon_CheckedPressedText  $btnIcon_Text
                                              btnIcon_CheckedIcon         $btnIcon_CheckedRule
                                              btnIcon_CheckedHotBk        $btnIcon_HotBk
                                              btnIcon_CheckedHotIcon      $btnIcon_CheckedRule
                                              btnIcon_CheckedPressedIcon  $btnIcon_CheckedRule""")

                .updateFlags(.Radio)
                .setTextPosition(.Right)
                .setForm(.Rectangle)
                .setCheckIndicator(.Left)
            }
        }
    }

    // The command row: the two verbs of the application on one side, what the machine
    // knows about the open capture on the other, and nothing in between. It keeps the same
    // height in the editor and in the library.
    mtd createCommandRow()
    {
        let metrics  = .themeMetrics()
        let cellSize = themeActionButtonSize(metrics)
        with .topBar = Wnd.create'Wnd(me, Math.Rectangle{0, 0, 0, cellSize})
        {
            .dockStyle       = .Top
            .backgroundStyle = .Window
        }

        with let verbs = StackLayoutCtrl.create(me.topBar, .Left, Math.Rectangle{0, 0, VerbsWidth, cellSize})
        {
            .dockStyle = .Left
            .spacing   = metrics.iconBar_ButtonGap
            .padding   = Math.Vector4{2 * metrics.iconBar_ButtonsPadding, metrics.iconBar_ButtonsPadding, 2 * metrics.iconBar_ButtonsPadding, metrics.iconBar_ButtonsPadding}
        }

        // Capture is the primary Voltage action. Library has the same push-button shape and
        // footprint, and takes the theme's alternate tone only while its page is active (see
        // updateLibraryButtonAppearance).
        .captureBtn = PushButton.create(verbs, "", Math.Rectangle{0, 0, 104, cellSize - 2 * metrics.iconBar_ButtonsPadding}, ActionCapture.DoIt, .Strong)

        with .libraryBtn = PushButton.create(verbs, appStrings().act_Library, Math.Rectangle{0, 0, 104, cellSize - 2 * metrics.iconBar_ButtonsPadding}, ActionGlobal.ShowLibrary)
        {
            .setIcon(me.icon(.Library))
        }

        with .commandReadouts = StackLayoutCtrl.create(me.topBar, .Right, Math.Rectangle{0, 0, ReadoutsWidth, cellSize})
        {
            .dockStyle = .Right
            .spacing   = metrics.iconBar_ButtonGap
            .padding   = Math.Vector4{2 * metrics.iconBar_ButtonsPadding, metrics.iconBar_ButtonsPadding, 2 * metrics.iconBar_ButtonsPadding, metrics.iconBar_ButtonsPadding}
        }

        // Zoom keeps its menu, so it stays a button; size is a pure readout and is not
        // one. Both carry the fixed-width family, so neither jumps as its value changes.
        with .zoomBtn = IconButton.create(.commandReadouts, {}, Math.Rectangle{0, 0, ReadoutWidth, cellSize - 2 * metrics.iconBar_ButtonsPadding})
        {
            .updateFlags(.CenterContent)
            .setArrowPosition(.RightDownward)
            .setForm(.Rectangle)
            .style.setFont(me.theme().res.fontDefaultFs)
            .sigPressed += func|main = me|(btn)
            {
                with let menu = MenuCtrl.createPopup(main)
                {
                    .updateFlags(.HideShortcuts)
                    .addItem(ActionZoom.Zoom1)
                    .addItem(ActionZoom.ZoomFit)
                }

                discard menu.doModal(assume cast(*IconButton, btn), autoDestroy: true)
            }
        }

        with .sizeBtn = IconButton.create(.commandReadouts, {}, Math.Rectangle{0, 0, ReadoutWidth, cellSize - 2 * metrics.iconBar_ButtonsPadding})
        {
            .updateFlags(.CenterContent | .Flat)
            .style.setFont(me.theme().res.fontDefaultFs)
            .setTextColor(me.themeColors().label_TextLight)
        }
    }

    // Applies the "show tool labels" option. The label never goes under the glyph, which
    // would double the height of every cell to carry a word the tooltip already carries;
    // it widens the rail and sits beside it.
    mtd setToolRailWidth()
    {
        let metrics    = .themeMetrics()
        let showLabels = .editorOptions.showToolBarLabels

        let cellSize    = themeActionButtonSize(metrics)
        let cellPadding = (cellSize - themeActionIconSize(metrics)) * 0.5
        let width       = showLabels ? RailLabelWidth : cellSize

        for c in .toolRail.children
        {
            let button = catch cast(*IconButton?, c)
            if not button do
                continue
            if showLabels do
                button.updateFlags(remove: .IconOnly)
            else do
                button.updateFlags(.IconOnly)
            button.setAllPaddings(Math.Vector4{cellPadding, 0, cellPadding, 0})

            button.position.width  = width
            button.position.height = cellSize
        }

        .toolRail.position.width = width

        // The rail width is assigned directly, so arrange its rows explicitly. The main layout
        // then gives the editor its final rectangle and sends its single required resize event.
        .toolRail.sendResizeEvent()
        .applyLayout()
        .toolRail.invalidate()
        .editWnd.invalidate()
    }

    // The caption action offering the palettes, the languages and the About box. The control
    // applies a choice itself; the application only persists it and refreshes what it caches.
    mtd createAppearanceButton()
    {
        with .appearanceButton = AppearanceButton.create(unwrap .surface, "capture.appearance")
        {
            .sigThemeChanged += func|main = me|(button)
            {
                main.editorOptions.theme = button.appearanceTheme
                main.editWnd.getCapture()?.invalidateAllFormCaches()
                main.saveAppState()
            }

            .sigLanguageChanged += func|main = me|(button)
            {
                if button.language.isEmpty() do
                    main.editorOptions.language = .System
                elif button.language == "fr" do
                    main.editorOptions.language = .French
                else do
                    main.editorOptions.language = .English
                main.saveAppState()
            }

            .sigAboutRequested += func|main = me|(_)
            {
                main.postCommandEvent(ActionAbout.About)
            }
        }
    }

    // The caption gear opens the application's global options directly.
    mtd createOptionsButton()
    {
        with .optionsButton = CaptionButton.create(unwrap .surface, ThemeIcons.Options, "capture.options")
        {
            .toolTip    = appStrings().act_Options
            .sigPressed += func|main = me|(_) { main.postCommandEvent(ActionOptions.Options) }
        }
    }

    // The edit area. The host supplies the structural gutter behind the rounded view: put
    // directly on the Window ground, the exposed corner pixels would read as a second panel
    // underneath it.
    mtd createEditArea()
    {
        with .editBar = Wnd.create'Wnd(me)
        {
            .dockStyle       = .Center
            .backgroundStyle = .ToolBar
            .padding.y       = me.themeMetrics().panel_GutterSize
        }

        with .editWnd = EditWnd.create(me, me.editBar)
        {
            .dockStyle            = .Center
            .backgroundStyle      = .Transparent
            .sigScrollSizeChanged += func|main = me|(_, _, _) { main.updateZoomDisplay() }
        }
    }

    // The strip of recent captures. Its preview size is a View menu choice: a control shown at
    // all times to set a preference costs permanent room and buys one occasional click.
    mtd createRecentBar()
    {
        let panelGutter = .themeMetrics().panel_GutterSize
        with .recentBar = Wnd.create'Wnd(me, {0, 0, 0, 136})
        {
            .dockStyle       = .Bottom
            .backgroundStyle = .ToolBar
            .padding         = Math.Vector4{0, panelGutter, panelGutter, 0}
        }

        with .recentWnd = RecentWnd.create(me.recentBar, me)
        {
            .dockStyle = .Center
        }
    }

    // The tool panel on the right: one column, one heading naming the tool it edits, the quick
    // styles of that tool above and its properties below.
    mtd createToolPanel()
    {
        let panelGutter = .themeMetrics().panel_GutterSize
        with .rightBar = Wnd.create'Wnd(me, Math.Rectangle{0, 0, RightPanelWidth + 2 * panelGutter, 0})
        {
            .dockStyle       = .Right
            .backgroundStyle = .ToolBar
            .padding         = Math.Vector4{panelGutter, panelGutter, panelGutter, 0}
        }

        with let rightPanel = Wnd.create'Wnd(me.rightBar, {0, 0, RightPanelWidth, 0})
        {
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
        }

        with .quickStyleBar = SplitterCtrl.create(rightPanel, {0, 0, RightPanelWidth, 600}, vertical: true)
        {
            .dockStyle       = .Center
            .backgroundStyle = .ToolBar
        }

        with let quickPane = Wnd.create'Wnd(me.quickStyleBar)
        {
            .backgroundStyle = .Panel
        }

        // The heading starts on the same margin as the cells and the rows under it: a title
        // centred over a left-aligned column is a second alignment on one narrow panel.
        with .toolTitle = Label.create(quickPane, "", {0, 0, 0, ToolTitleHeight})
        {
            .dockStyle = .Top
            .style.setFont(me.theme().res.fontDefaultFs)
            .setTextAlignment(.Left, .Center)
            .setTextPadding({12, 8, 12, 0})
            .setTextColor(me.themeColors().label_TextLight)
        }

        with .quickWnd = QuickWnd.create(quickPane, me)
        {
            .dockStyle = .Center
        }

        with let propPane = Wnd.create'Wnd(me.quickStyleBar)
        {
            .backgroundStyle = .Panel
        }

        with .propWnd = PropWnd.create(propPane, me)
        {
            .dockStyle = .Center
        }

        .quickStyleBar.addPane(quickPane).preserveSize = true
        discard .quickStyleBar.addPane(propPane)
        .quickStyleBar.setPaneSize(0, 168 + ToolTitleHeight)
    }
}
