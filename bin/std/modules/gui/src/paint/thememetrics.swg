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

        // Transparent margin the drop shadow is cast into. It has to hold the spread plus the offset,
        // or the shadow is cut off by the edge of the window instead of fading out into it.
        surfaceWnd_ShadowSize:    f32 = 18
        surfaceWnd_CornerRadius:  f32 = 18     // Corner of a surface. The Swag palette softens it to 12; see setSwagGeometry.
        surfaceWnd_ShadowSpread:  f32 = 14     // How far the drop shadow reaches out from the body.
        surfaceWnd_ShadowOffsetX: f32 = 0      // Sideways displacement of the drop shadow.
        surfaceWnd_ShadowOffsetY: f32 = 4      // Downward displacement of the drop shadow, which is what lifts the window.

        wnd_BorderSize:            f32 = 1        // Thickness of the outline of a surface.
        wnd_BigCaptionCY:          f32 = 42       // Height of a large caption.
        wnd_SmallCaptionCY:        f32 = 36       // Compact caption height; leaves balanced air around its title and controls.
        wnd_CaptionMarginTitle:    f32 = 14       // Air between the leading edge of a caption and its icon or title.
        wnd_CaptionIconSize:       f32 = 20       // Side of the mark a drawn caption shows beside its title.
        wnd_CaptionButtonMargin:   f32 = 5        // Air around a caption button, inside the caption band.
        wnd_CaptionButtonGlyph:    f32 = 16       // Side of a caption glyph. Chrome, so it sits at the row size of the chart.
        wnd_CaptionButtonAspect:   f32 = 1.35     // Width of a caption button as a multiple of its height.
        wnd_CaptionButtonMinWidth: f32 = 44       // Narrowest a caption button gets.
        wnd_SizingBorderSize:      f32 = 8        // Reach of the resizing border on each side of a surface edge.
        wnd_TopSizingBorderSize:   f32 = 7        // Reach of the resizing border along the top edge, capped by the side reach.

        tabBar_FlatHeight:   f32 = 40     // Height of a flat tab bar.
        tabBar_RoundHeight:  f32 = 28     // Height of a round tab bar.
        tabBar_ButtonHeight: f32 = 32     // Height of a button tab bar.

        // The button a bar grows when it cannot show every tab. It is chrome standing in the row
        // of tabs, so the glyph keeps air inside the button and the button keeps air on both
        // sides: drawn at the size of the button it read as an arrow wedged into a circle.
        tabBar_PopupButtonSize:   f32 = 24     // Side of the overflow button.
        tabBar_PopupButtonGlyph:  f32 = 16     // Side of its glyph.
        tabBar_PopupButtonMargin: f32 = 8      // Air it keeps from the last tab, and from the edge of the bar.

        btnPush_Padding:    f32 = 5       // Inset of the caption area of a push button.
        btnPush_TextMargin: f32 = 14      // Room a measured caption keeps on each side of a push button.
        btnPush_Width:      f32 = 100     // Default and minimum width of a push button.
        btnPush_Height:     f32 = 30      // Height of a push button.

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

        dialog_Padding:    f32 = 24     // Outer inset kept around dialog content and action rows.
        dialog_BtnPadding: f32 = 8      // Gap between dialog actions and vertical inset of their bar.

        editBox_SquarePadding: Math.Vector4 = {10, 5, 10, 5}     // Inset of the text of a square-cornered field.
        editBox_RoundPadding:  Math.Vector4 = {12, 5, 12, 5}     // Inset of the text of a round field.
        editBox_FlatPadding:   Math.Vector4 = {12, 0, 12, 5}     // Inset of the text of a flat field.
        editBox_Width:         f32          = 100                // Default width of a field.
        editBox_Height:        f32          = 32                 // Height of a field.
        editBox_UnitMargin:    f32          = 3                  // Air between the value of a field and its unit.

        btnToggle_Width:  f32 = 50     // Width of a toggle.
        btnToggle_Height: f32 = 26     // Height of a toggle.

        slider_Width:     f32 = 200     // Default width of a slider.
        slider_Height:    f32 = 26      // Height of a slider.
        slider_TrackSize: f32 = 18      // Thickness of the track of a slider.
        slider_BoxSize:   f32 = 12      // Side of the thumb; an indicator, not a control to grab with a finger.
        slider_StepSize:  f32 = 6       // Side of the tick marking a step of a slider.

        circular_Size:       f32 = 40     // Side of a circular control.
        circular_MarkerSize: f32 = 5      // Radius of the marker of a circular control.

        menuPopup_Padding:         f32 = 12     // Inset of the entries of a popup menu.
        menuPopup_SpaceLines:      f32 = 6      // Air between two entries of a popup menu, shared by their hover grounds.
        menuPopup_ShadowSize:      f32 = 10     // Reach of the shadow a popup menu casts.
        menuPopup_ItemHeight:      f32 = 24     // Complete pitch of an ordinary menu entry, including the inter-entry air.
        menuPopup_IconSize:        f32 = 16     // Side of a menu-entry glyph or check mark.
        menuPopup_IconMargin:      f32 = 6      // Air between the active rule and the glyph of an entry.
        menuPopup_IconTextMargin:  f32 = 10     // Air between the glyph or check mark of an entry and its wording.
        menuPopup_SeparatorHeight: f32 = 8      // Height of a separator entry.
        menuPopup_BarItemOverlap:  f32 = 12     // Depth by which a popup menu and the menu bar entry that opened it overlap.
        menuPopup_WindowMargin:    f32 = 8      // Air between a popup menu and the edge of its window.

        menuBar_Height:       f32 = 30     // Height of a menu bar.
        menuBar_SpaceBetween: f32 = 24     // Air between two menu bar entries.

        iconBar_ButtonsPadding: f32 = 4     // Air between the buttons of an icon bar.

        scrollBar_NormalSize: f32 = 20     // Thickness of a scroll bar.
        scrollBar_SmallSize:  f32 = 10     // Thickness of a compact scroll bar.
        scrollBar_BoxPadding: f32 = 4      // Air between a scroll bar thumb and its track.
        scrollBar_BoxMinSize: f32 = 20     // Shortest a scroll bar thumb gets.

        comboBox_Width:          f32 = 150     // Default width of a combo box.
        comboBox_Height:         f32 = 32      // Height of a combo box.
        comboBox_RightMargin:    f32 = 30      // Room kept for the drop-down marker at the trailing edge of a combo box.
        comboBox_Padding:        f32 = 10      // Leading inset of the content of a combo box.
        comboBox_IconTextMargin: f32 = 6       // Air between the glyph and the wording of a combo box entry.

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

        frameWnd_SquarePadding:            f32 = 5                           // Inset of the view of a square frame.
        frameWnd_RoundPadding:             f32 = 5                           // Inset of the view of a round frame.
        frameWnd_FlatPadding:              f32 = 2                           // Inset of the view of a flat frame.
        frameWnd_SmallShadowSize:          Math.Vector4 = {5, 5, 15, 15}     // Reach of the compact frame shadow on the left, top, right, and bottom.
        frameWnd_AnchorWidth:              f32 = 24                          // Width of a callout anchor along the frame edge.
        frameWnd_AnchorHeight:             f32 = 10                          // Depth a callout anchor protrudes from the frame.
        frameWnd_AnchorOverlap:            f32 = 2                           // Depth by which a callout anchor overlaps the frame it leaves.
        frameWnd_AnchorRoundBorderMargin:  f32 = 16                          // Closest a callout anchor comes to a corner of a round frame.
        frameWnd_AnchorSquareBorderMargin: f32 = 8                           // Closest a callout anchor comes to a corner of a square frame.

        list_Padding:    f32 = 8      // Outer inset separating list rows from their frame.
        list_ExpandSize: f32 = 22     // Width of the disclosure column of a tree row.

        header_Height:    f32 = 35                          // Height of a column header.
        header_Padding:   Math.Vector4 = {10, 5, 10, 5}     // Inset of the caption of a column header.
        header_Separator: f32 = 5                           // Width of the grip between two column headers.

        panel_GutterSize:  f32 = 4     // Gap separating a structural panel from adjacent application chrome.
        splitView_BarSize: f32 = 5     // Draggable gap between split panels, one pixel wider than the outer gutter.

        progressBar_Height:     f32 = 18      // Height of a progress bar.
        progressBar_ClipOffset: f32 = 2       // Inset of the filled part inside the progress bar track.
        progressBar_SpeedInf:   f32 = 0.5     // Sweeps per second of an indeterminate progress bar.

        spinner_Size:     f32 = 24      // Side of a spinner created without a size.
        spinner_DotCount: f32 = 8       // Number of dots forming the ring.
        spinner_Speed:    f32 = 1.1     // Turns of the ring per second.

        colorPicker_RoundPick:  f32 = 6     // Side of the round marker of the picked color.
        colorPicker_SquarePick: f32 = 6     // Side of the square marker of the picked color.

        label_Height: f32 = 24     // Height of a label created without one.

        separator_HairlineSize: f32 = 1     // Thickness of a hairline separator.
        separator_AccentSize:   f32 = 4     // Thickness of an accent separator.

        // The rule that marks an active tool or tab. It is thin, and it stops short of both ends
        // by `activeRail_Margin` so it keeps its distance from the content it marks.
        activeRail_Size:   f32 = 3     // Thickness of the rule.
        activeRail_Margin: f32 = 8     // Air the mark keeps at each end, and between the rule and the content.

        // The ring that says where the keyboard is. It is a rule around a control, not a fill on
        // it, and it keeps clear of the control's own border so the two never read as one thick edge.
        //
        // Its corner is the corner of the control it marks, taken from the tile that control paints
        // and stepped in by the inset so the two stay concentric. `focusRing_Radius` is the corner it
        // keeps of its own, so a control with square edges is still marked by a ring and not by a box.
        focusRing_Size:   f32 = 1     // Thickness of the ring.
        focusRing_Inset:  f32 = 3     // Air the ring keeps inside the control's rectangle.
        focusRing_Radius: f32 = 3     // Softest corner the ring takes when the control lends it none.

        richEdit_Padding: f32 = 5     // Inset of the text of a rich editor.

        // A tool tip is exactly as large as the words it holds. It wraps rather than grow past
        // `toolTip_MaxWidth`, it ends its last line with an ellipsis rather than grow past
        // `toolTip_MaxHeight`, and it never scrolls — so both caps are a promise about the
        // largest box a reader can be shown, not a viewport onto a longer text.
        toolTip_Padding:   Math.Vector4 = {8, 6, 8, 6}     // Inset between a tool tip's border and its text.
        toolTip_MaxWidth:  f32 = 360                       // Width at which a tool tip wraps instead of growing.
        toolTip_MaxHeight: f32 = 200                       // Height at which a tool tip truncates instead of growing.
        toolTip_Offset:    f32 = 12                        // Gap a tool tip keeps from the pointer that summoned it.
    }
}

// Returns the side of a primary action glyph shown in an application or viewer bar.
func themeActionIconSize(metrics: const *ThemeMetrics)->f32 => metrics.wnd_CaptionIconSize

// Returns the side of a supporting glyph shown in a menu, list, field, or compact header.
func themeRowIconSize(metrics: const *ThemeMetrics)->f32 => metrics.menuPopup_IconSize

// Returns the side of an ordinary icon-button cell in an application or viewer bar.
func themeActionButtonSize(metrics: const *ThemeMetrics)->f32 => themeActionIconSize(metrics) + 2 * metrics.btnIcon_Padding

// Returns the side of a compact icon-button cell in a panel or list header.
func themeCompactButtonSize(metrics: const *ThemeMetrics)->f32 => metrics.editBox_Height

// Returns the width of an action cell that also carries a drop-down arrow.
func themeDropDownButtonWidth(metrics: const *ThemeMetrics)->f32 => themeActionButtonSize(metrics) + 2 * metrics.btnIcon_SpacingArrowH
