#global public

using Core

// Defines logical dimensions, spacing, and animation timing for themed GUI elements.
struct ThemeMetrics
{
    public
    {
        defaultFontSize:      u32 = 13     // Size of the interface font.
        defaultFixedFontSize: u32 = 14     // Size of the fixed-width font.

        motion_QuickSeconds: f32 = 0.12     // Duration of hover, selection, and other immediate state feedback.
        motion_PageSeconds:  f32 = 0.18     // Duration of a page change.
        motion_PanelSeconds: f32 = 0.22     // Duration of a layout-affecting panel change.
        motion_PageOffset:   f32 = 16       // Travel distance of a page change, in logical pixels.
        motion_LeaveSeconds: f32 = 0.12     // Duration of a floating surface fading out: two thirds of its arrival.
        motion_EdgeTravel:   f32 = 8        // Travel of a floating surface arriving from the edge it stands against.
        motion_AnchorTravel: f32 = 4        // Travel of a floating surface leaving the anchor it belongs to.

        // The corners of the charter, one per kind of shape. The atlas tiles of
        // [[Gui.ThemeImageRects]] are drawn with these radii and publish them as their `radius`; a
        // part painted in code rather than from a tile takes its corner from here.
        corner_Floating: f32 = 12     // Corner of a floating surface: a lens, a sheet, an inspector, a dialog, a popover.
        corner_Menu:     f32 = 10     // Corner of a menu and of a popup list.
        corner_Control:  f32 = 6      // Corner of a button, a field, a combo box, a segment frame, a tool tip.
        corner_Chip:     f32 = 4      // Corner of a chip, a swatch, a keycap, an inner segment, a check box.

        // Heights of a button or a field in the two contexts that do not use the ordinary 32.
        control_DialogHeight:    f32 = 34     // Height of a button or a field inside a dialog.
        control_InspectorHeight: f32 = 28     // Height of a button or a field inside an inspector.

        // Transparent margin the drop shadow is cast into. It has to hold the spread plus the offset,
        // or the shadow is cut off by the edge of the window instead of fading out into it.
        surfaceWnd_ShadowSize:    f32 = 18
        surfaceWnd_CornerRadius:  f32 = 10     // Corner of a window.
        surfaceWnd_ShadowSpread:  f32 = 14     // How far the drop shadow reaches out from the body.
        surfaceWnd_ShadowOffsetX: f32 = 0      // Sideways displacement of the drop shadow.
        surfaceWnd_ShadowOffsetY: f32 = 4      // Downward displacement of the drop shadow, which is what lifts the window.

        // The top strip of a window is ground the content sits on, not a band: a faint glyph at its
        // leading corner, the title centred in small faint type, and faint window buttons at its
        // trailing end. On an application window it floats over the view, which reaches the top
        // edge; see [[Gui.SurfaceWnd.stripHeight]] and [[Gui.Wnd.stripInset]].
        wnd_BorderSize:            f32 = 1       // Thickness of the outline of a surface.
        wnd_StripHeight:           f32 = 52      // Height of the top strip of an application window, floating over its content.
        wnd_SmallCaptionCY:        f32 = 36      // Height of the top strip of a dialog or a tool window, kept above its content.
        wnd_CaptionButtonHeight:   f32 = 32      // Tallest a window button gets; it is centred in the strip.
        wnd_CaptionMarginTitle:    f32 = 18      // Air between the leading edge of a window and its glyph.
        wnd_CaptionIconSize:       f32 = 18      // Side of the application glyph in the corner of a window.
        wnd_TitleFontSize:         u32 = 12      // Size of the title centred in the top strip.
        wnd_CaptionButtonMargin:   f32 = 5       // Air around a window button, inside the top strip.
        wnd_CaptionButtonGap:      f32 = 2       // Air between neighboring window buttons.
        wnd_CaptionActionGap:      f32 = 8       // Air between an application action in the top strip and its neighbors.
        wnd_CaptionButtonGlyph:    f32 = 16      // Side of a window button glyph. Chrome, so it sits at the row size of the chart.
        wnd_CaptionButtonAspect:   f32 = 0.9     // Width of a window button as a multiple of its height.
        wnd_CaptionButtonMinWidth: f32 = 30      // Narrowest a window button gets.
        wnd_SizingBorderSize:      f32 = 8       // Reach of the resizing border on each side of a surface edge.
        wnd_TopSizingBorderSize:   f32 = 7       // Reach of the resizing border along the top edge, capped by the side reach.

        action_IconSize: f32 = 20     // Side of a primary action glyph in an application or viewer bar.

        tabBar_FlatHeight:   f32 = 40     // Height of a flat tab bar.
        tabBar_RoundHeight:  f32 = 32     // Height of a round tab bar: a segment group.
        tabBar_ButtonHeight: f32 = 32     // Height of a button tab bar.
        tabBar_SegmentInset: f32 = 3      // Air between the raised frame of a segment group and the chosen segment.

        // The button a bar grows when it cannot show every tab. It is chrome standing in the row
        // of tabs, so the glyph keeps air inside the button and the button keeps air on both
        // sides: drawn at the size of the button it read as an arrow wedged into a circle.
        tabBar_PopupButtonSize:   f32 = 24     // Side of the overflow button.
        tabBar_PopupButtonGlyph:  f32 = 16     // Side of its glyph.
        tabBar_PopupButtonMargin: f32 = 8      // Air it keeps from the last tab, and from the edge of the bar.

        btnPush_Padding:    f32 = 5       // Inset of the caption area of a push button.
        btnPush_TextMargin: f32 = 14      // Room a measured caption keeps on each side of a push button.
        btnPush_Width:      f32 = 100     // Default and minimum width of a push button.
        btnPush_Height:     f32 = 32      // Height of a push button.

        iconText_Margin: f32 = 8     // Air between a glyph and the word it leads. Air is the first separator, so it is generous.

        // Side of the box a chevron is drawn in — the drop-down of a field, the submenu marker of a
        // menu entry, the disclosure of a tree or a property row, the sort order of a column, the
        // arrow of a menu button. One decision for all of them, because they are one glyph
        // ([[Gui.ThemeIcons.ChevronDown]] and its three siblings) and a reader reads them as one.
        //
        // It is an indicator, not a control, so it sits at the smallest cell of the chart: the ink is
        // five sixths of this box wide and half that tall.
        chevron_Size: f32 = 12

        btnCheck_Size:    f32 = 24     // Side of the box of a check box or radio button.
        btnCheck_Padding: f32 = 4      // Air between the box of a check box and its wording.

        // A dialog is a floating sheet: one inset around its title, its body and its actions, one
        // gap between two pieces of its body (twice the gap between two actions).
        dialog_Padding:       f32 = 28     // Inset kept around the title, the body and the actions of a dialog.
        dialog_BtnPadding:    f32 = 8      // Gap between two actions of a dialog; twice it parts two pieces of its body.
        dialog_TitleFontSize: u32 = 17     // Size of the title that opens the body of a dialog.
        dialog_MarkSize:      f32 = 8      // Diameter of the critical dot before the title of a failure.
        dialog_TileSize:      f32 = 52     // Side of the application tile that leads an about box.
        dialog_NameFontSize:  u32 = 21     // Size of the product name beside the tile of an about box.

        editBox_SquarePadding: Math.Vector4 = {10, 5, 10, 5}     // Inset of the text of a square-cornered field.
        editBox_RoundPadding:  Math.Vector4 = {12, 5, 12, 5}     // Inset of the text of a round field.
        editBox_FlatPadding:   Math.Vector4 = {12, 0, 12, 5}     // Inset of the text of a flat field.
        editBox_Width:         f32          = 100                // Default width of a field.
        editBox_Height:        f32          = 32                 // Height of a field.
        editBox_UnitMargin:    f32          = 3                  // Air between the value of a field and its unit.

        btnToggle_Width:  f32 = 34     // Width of a switch.
        btnToggle_Height: f32 = 20     // Height of a switch.

        slider_Width:     f32 = 200     // Default width of a slider.
        slider_Height:    f32 = 26      // Height of a slider.
        slider_TrackSize: f32 = 18      // Height of the band the track tile is drawn in; the tile draws a two-pixel rule at its center.
        slider_BoxSize:   f32 = 14      // Side of the knob.
        slider_StepSize:  f32 = 6       // Side of the tick marking a step of a slider.

        circular_Size:       f32 = 40     // Side of a circular control.
        circular_MarkerSize: f32 = 5      // Radius of the marker of a circular control.

        menuPopup_Padding:         f32 = 6      // Inset of the entries of a popup menu.
        menuPopup_SpaceLines:      f32 = 8      // Air between two entries of a popup menu, shared by their hover grounds.
        menuPopup_ShadowSize:      f32 = 10     // Reach of the shadow a popup menu casts.
        menuPopup_ItemHeight:      f32 = 30     // Complete pitch of an ordinary menu entry, including the inter-entry air.
        menuPopup_IconSize:        f32 = 16     // Side of a menu-entry glyph or check mark.
        menuPopup_IconMargin:      f32 = 6      // Air between the active rule and the glyph of an entry.
        menuPopup_IconTextMargin:  f32 = 10     // Air between the glyph or check mark of an entry and its wording.
        menuPopup_SeparatorHeight: f32 = 9      // Height of a separator entry.
        menuPopup_SeparatorInset:  f32 = 4      // Inset of a separator rule past the padding, so it stops ten pixels from each edge.
        menuPopup_ShortcutSize:    u32 = 11     // Size of the fixed-width face a shortcut is written in.
        menuPopup_BarItemOverlap:  f32 = 12     // Depth by which a popup menu and the menu bar entry that opened it overlap.
        menuPopup_WindowMargin:    f32 = 8      // Air between a popup menu and the edge of its window.

        // An option sheet: one row per setting, the pages of its choices sliding inside one frame.
        optionSheet_Width:           f32 = 300     // Width of an anchored sheet, and of the column of a bottom sheet.
        optionSheet_SidePanelWidth:  f32 = 380     // Width of a side panel, before the window bounds it.
        optionSheet_RowHeight:       f32 = 34      // Pitch of a row holding one line.
        optionSheet_DetailRowHeight: f32 = 44      // Pitch of a row whose wording carries a detail line.
        optionSheet_HeaderHeight:    f32 = 40      // Height of the band that titles a page and leads back from it.
        optionSheet_HeadingHeight:   f32 = 28      // Height of the title of a group of rows.
        optionSheet_Inset:           f32 = 6       // Air between the edge of a sheet and the grounds of its rows.
        optionSheet_RowPadding:      f32 = 10      // Air between the ground of a row and what it shows.
        optionSheet_ValueMaxWidth:   f32 = 150     // Widest the current value of a row grows before it is shortened.

        // The floating components of the charter — the lens, the information sheet, the inspector,
        // the mini-bar and the dock — stand on the surface ground with a hairline ring and a
        // shadow, above the work and away from the window edges.
        floating_ShadowBlur:    f32 = 64     // Width over which the shadow of a floating surface fades out, centred on the edge of its offset body.
        floating_ShadowOffsetY: f32 = 24     // Downward displacement of the shadow of a floating surface: the light falls from above.
        floating_Inset:         f32 = 24     // Air between a floating panel and the window edges it stands beside.

        // A section label: small spaced capitals in the faint ink, with no band behind them.
        sectionLabel_FontSize:      u32 = 10      // Size of the face a section label is set in.
        sectionLabel_LetterSpacing: f32 = 1.5     // Air added between the capitals of a section label.

        // A keycap writes a key in a chip, the way the hint line and the foot of the lens teach it.
        keycap_Height:   f32 = 18     // Height of a keycap.
        keycap_Padding:  f32 = 7      // Air between the edge of a keycap and the name of its key.
        keycap_FontSize: u32 = 11     // Size of the name of a key.

        // The hint line teaches the door: a keycap and what it opens, faint, near the bottom edge.
        hintLine_Bottom:   f32 = 24     // Air between the hint line and the bottom edge of the window.
        hintLine_Height:   f32 = 24     // Height of the hint line.
        hintLine_FontSize: u32 = 12     // Size of the words and of the reading of the hint line.
        hintLine_KeyGap:   f32 = 8      // Air between a keycap and the words it leads.
        hintLine_GroupGap: f32 = 24     // Air between two hints, and between the reading and the first hint.

        // The lens: one input over results grouped under section labels, keys at its foot.
        lens_Width:          f32 = 640      // Widest the lens gets; a narrow window keeps the floating inset on both sides.
        lens_TopRatio:       f32 = 0.15     // Height of the window above the lens, as a fraction of the window.
        lens_MaxHeightRatio: f32 = 0.7      // Tallest the lens gets, as a fraction of the window.
        lens_InputHeight:    f32 = 64       // Height of the input band.
        lens_InputFontSize:  u32 = 22       // Size of the query typed in the input.
        lens_TextInset:      f32 = 24       // Air between the edge of the lens and its words.
        lens_RowInset:       f32 = 8        // Air between the edge of the lens and the ground of a row.
        lens_RowHeight:      f32 = 40       // Height of a result row.
        lens_RowFontSize:    u32 = 14       // Size of the title of a result.
        lens_LeadWidth:      f32 = 36       // Width of the column holding the glyph or the number that leads a row.
        lens_SectionHeight:  f32 = 32       // Height of the label that opens a group of results.
        lens_FooterHeight:   f32 = 40       // Height of the band listing the keys.

        // The information sheet a key opens: a title, an identity line, facts and readings.
        infoSheet_Width:         f32 = 340     // Width of an information sheet.
        infoSheet_Padding:       f32 = 28      // Air between the edge of an information sheet and what it holds.
        infoSheet_TitleFontSize: u32 = 21      // Size of the title of an information sheet.
        infoSheet_FactFontSize:  u32 = 28      // Size of a fact the reader came for.
        infoSheet_LabelWidth:    f32 = 96      // Width of the label column of the readings.
        infoSheet_LineHeight:    f32 = 24      // Pitch of a reading.
        infoSheet_BlockGap:      f32 = 16      // Air between two blocks of an information sheet.
        infoSheet_LineGap:       f32 = 4       // Air under the title, and under a paragraph.

        // The inspector: the sheet's shape docked at the trailing edge, holding the properties of a selection.
        inspector_Width:         f32 = 304     // Width of an inspector.
        inspector_Padding:       f32 = 20      // Air between the edge of an inspector and what it holds.
        inspector_LabelWidth:    f32 = 88      // Width of the label column of an inspector.
        inspector_LabelGap:      f32 = 12      // Air between a label and its editor.
        inspector_RowGap:        f32 = 10      // Air between two rows of an inspector.
        inspector_SectionHeight: f32 = 30      // Height of the label that opens a section of an inspector.
        inspector_TitleFontSize: u32 = 15      // Size of the title of an inspector.

        // The mini-bar: a small floating toolbar placed next to the selected object.
        miniBar_Padding:         f32 = 4      // Air between the edge of the mini-bar and its buttons.
        miniBar_ButtonSize:      f32 = 28     // Side of a button of the mini-bar.
        miniBar_Corner:          f32 = 8      // Corner of the mini-bar.
        miniBar_Gap:             f32 = 2      // Air between two items of the mini-bar.
        miniBar_SeparatorHeight: f32 = 16     // Height of the hairline between two groups of the mini-bar.
        miniBar_SeparatorGap:    f32 = 6      // Air on each side of that hairline.
        miniBar_Distance:        f32 = 12     // Air between the mini-bar and the selection it stands next to.

        // The dock: a vertical floating column of tools at the leading edge, vertically centred.
        toolDock_Padding:  f32 = 6      // Air between the edge of the dock and its cells.
        toolDock_CellSize: f32 = 36     // Side of a cell of the dock.
        toolDock_Glyph:    f32 = 18     // Side of the glyph of a tool.
        toolDock_Gap:      f32 = 2      // Air between two cells of the dock.

        menuBar_Height:       f32 = 30     // Height of a menu bar.
        menuBar_SpaceBetween: f32 = 24     // Air between two menu bar entries.

        iconBar_ButtonsPadding: f32 = 4     // Inset around the buttons of an icon bar.
        iconBar_ButtonGap:      f32 = 8     // Air between neighboring buttons of an icon bar.

        scrollBar_NormalSize: f32 = 10     // Thickness of a scroll bar: a six-pixel thumb and its air.
        scrollBar_SmallSize:  f32 = 8      // Thickness of a compact scroll bar.
        scrollBar_BoxPadding: f32 = 2      // Air between a scroll bar thumb and its track.
        scrollBar_BoxMinSize: f32 = 20     // Shortest a scroll bar thumb gets.

        comboBox_Width:          f32 = 150     // Default width of a combo box.
        comboBox_Height:         f32 = 32      // Height of a combo box.
        comboBox_RightMargin:    f32 = 30      // Room kept for the drop-down marker at the trailing edge of a combo box.
        comboBox_Padding:        f32 = 10      // Leading inset of the content of a combo box.
        comboBox_IconTextMargin: f32 = 6       // Air between the glyph and the wording of a combo box entry.

        stepper_Width:       f32 = 120     // Default width of a stepper.
        stepper_ButtonInset: f32 = 3       // Air between the frame of a stepper and its two buttons.
        stepper_Glyph:       f32 = 14      // Side of the `−` and `+` glyphs of a stepper: quiet beside the value.

        popupList_Padding:          f32 = 6     // Minimum leading inset of popup-list content.
        popupList_IconTextMargin:   f32 = 6     // Air between the glyph and the wording of a popup-list entry.
        popupList_SeparatorPadding: f32 = 4     // Air a popup-list separator keeps at each end.

        btnIcon_Padding:       f32 = 8     // Symmetric outer air around an icon-button content group.
        btnIcon_ArrowSize:     f32 = 8     // Size of the disclosure marker beside an icon-button action.
        btnIcon_MarginArrow:   f32 = 4     // Air around the disclosure marker of an icon button.
        btnIcon_SpacingIcon:   f32 = 4     // Air between two glyphs of an icon button.
        btnIcon_SpacingArrowH: f32 = 8     // Air between an icon-button action and its disclosure marker.
        btnIcon_SpacingArrowV: f32 = 4     // Air between an icon-button action and a disclosure marker placed under it.
        btnIcon_SpacingTextH:  f32 = 8     // Air between the glyph of an icon button and wording set beside it.
        btnIcon_SpacingTextV:  f32 = 0     // Air between the glyph of an icon button and wording set under it.

        frameWnd_SquarePadding:            f32 = 5      // Inset of the view of a square frame.
        frameWnd_RoundPadding:             f32 = 5      // Inset of the view of a round frame.
        frameWnd_FlatPadding:              f32 = 2      // Inset of the view of a flat frame.
        frameWnd_SmallShadowSize:          Math.Vector4 = {5, 5, 15, 15}     // Reach of the compact frame shadow on the left, top, right, and bottom.
        frameWnd_AnchorWidth:              f32 = 24     // Width of a callout anchor along the frame edge.
        frameWnd_AnchorHeight:             f32 = 10     // Depth a callout anchor protrudes from the frame.
        frameWnd_AnchorOverlap:            f32 = 2      // Depth by which a callout anchor overlaps the frame it leaves.
        frameWnd_AnchorRoundBorderMargin:  f32 = 16     // Closest a callout anchor comes to a corner of a round frame.
        frameWnd_AnchorSquareBorderMargin: f32 = 8      // Closest a callout anchor comes to a corner of a square frame.

        list_Padding:    f32 = 8      // Outer inset separating list rows from their frame.
        list_LineHeight: f32 = 30     // Height of a list row, unless its font asks for more.
        list_ExpandSize: f32 = 22     // Width of the disclosure column of a tree row.

        header_Height:    f32 = 30     // Height of a column header.
        header_Padding:   Math.Vector4 = {10, 5, 10, 5}     // Inset of the caption of a column header.
        header_Separator: f32 = 5      // Width of the grip between two column headers.

        panel_GutterSize:  f32 = 8     // Gap separating a structural panel from adjacent application chrome.
        splitView_BarSize: f32 = 5     // Visible and draggable divider between split panels.

        // A property grid: marks set beside a name, and the rows of its condensed kind.
        property_ControlInset:       f32 = 4      // Inset of the state ground within a property control.
        property_ModifiedMarkSize:   f32 = 6      // Diameter of the Arc dot after the name of a value changed from its default.
        property_CondensedRowHeight: f32 = 26     // Height of a row of the condensed property grid.

        progressBar_Height:     f32 = 16      // Height of a progress bar created without one.
        progressBar_TrackSize:  f32 = 4       // Thickness of the track, centered in the bar.
        progressBar_SpeedInf:   f32 = 0.5     // Sweeps per second of an indeterminate progress bar.

        spinner_Size:       f32 = 24      // Side of a spinner created without a size.
        spinner_StrokeSize: f32 = 2       // Thickness of the ring and of the arc turning on it.
        spinner_ArcSweep:   f32 = 0.28    // Share of the ring the turning arc covers.
        spinner_Speed:      f32 = 1.1     // Turns of the arc per second.

        palPicker_SwatchInset: f32 = 3     // Air between the cell of a swatch and the chip it draws, which its ring stands in.

        colorPicker_RoundPick:  f32 = 6     // Side of the round marker of the picked color.
        colorPicker_SquarePick: f32 = 6     // Side of the square marker of the picked color.

        label_Height: f32 = 24     // Height of a label created without one.

        // A notice: a dot in its tone before the words, and a faint dismiss cross after them.
        embInfo_Padding:     f32 = 16     // Air between the leading edge of a notice and its dot.
        embInfo_DotSize:     f32 = 7      // Side of the dot of a notice.
        embInfo_DotGap:      f32 = 10     // Air between the dot and the words.
        embInfo_CloseSize:   f32 = 28     // Side of the dismiss button.
        embInfo_CloseGlyph:  f32 = 16     // Side of the dismiss glyph.
        embInfo_CloseMargin: f32 = 6      // Air around the dismiss button.

        separator_HairlineSize: f32 = 1     // Thickness of a hairline separator.

        // The underline of the active tab, and the rule a checked tool marked on one edge carries.
        // It stops short of both ends by `tabItem_RailMargin`, so it underlines the words.
        tabItem_RailSize:   f32 = 2     // Thickness of the underline.
        tabItem_RailMargin: f32 = 8     // Air the underline keeps at each end.

        // The ring that says where the keyboard is: two pixels around the control, two pixels away
        // from it, so it never merges with the control's own edge or fill.
        //
        // Its corner is the corner of the control it marks, taken from the tile that control paints
        // and stepped out by the offset so the two stay concentric. `focusRing_Radius` is the corner
        // it keeps of its own, so a control with square edges is still marked by a ring and not a box.
        focusRing_Size:   f32 = 2     // Thickness of the ring.
        focusRing_Offset: f32 = 2     // Air between the control's rectangle and the ring.
        focusRing_Radius: f32 = 4     // Softest corner the ring takes when the control lends it none.

        richEdit_Padding: f32 = 5     // Inset of the text of a rich editor.

        // A tool tip is exactly as large as the words it holds. It wraps rather than grow past
        // `toolTip_MaxWidth`, it ends its last line with an ellipsis rather than grow past
        // `toolTip_MaxHeight`, and it never scrolls — so both caps are a promise about the
        // largest box a reader can be shown, not a viewport onto a longer text.
        toolTip_Padding:   Math.Vector4 = {8, 5, 8, 5}     // Inset between a tool tip's border and its text.
        toolTip_FontSize:  u32 = 12      // Size of the face a tool tip is written in.
        toolTip_MaxWidth:  f32 = 360     // Width at which a tool tip wraps instead of growing.
        toolTip_MaxHeight: f32 = 200     // Height at which a tool tip truncates instead of growing.
        toolTip_Offset:    f32 = 12      // Gap a tool tip keeps from the pointer that summoned it.
    }
}

// Returns the side of a primary action glyph shown in an application or viewer bar.
func themeActionIconSize(metrics: const *ThemeMetrics)->f32 => metrics.action_IconSize

// Returns the side of a supporting glyph shown in a menu, list, field, or compact header.
func themeRowIconSize(metrics: const *ThemeMetrics)->f32 => metrics.menuPopup_IconSize

// Returns the side of an ordinary icon-button cell in an application or viewer bar.
func themeActionButtonSize(metrics: const *ThemeMetrics)->f32 => themeActionIconSize(metrics) + 2 * metrics.btnIcon_Padding

// Returns the side of a compact icon-button cell in a panel or list header.
func themeCompactButtonSize(metrics: const *ThemeMetrics)->f32 => metrics.editBox_Height

// Returns the width of an action cell that also carries a drop-down arrow.
func themeDropDownButtonWidth(metrics: const *ThemeMetrics)->f32 => themeActionButtonSize(metrics) + 2 * metrics.btnIcon_SpacingArrowH
