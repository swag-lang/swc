#global public

using Core

// Describes a scalable region in the theme atlas.
struct ThemeImageRect
{
    public
    {
        rect:   Math.Rectangle     // Region of the atlas the part is drawn from, in authored atlas texels.
        corner: f32     // Side of the nine-slice corner regions, in authored atlas texels; zero stretches the whole region.

        // Corner the tile draws, in logical pixels, for the parts that have to follow that shape
        // without drawing it — the keyboard-focus ring is one. Zero means the tile has no single
        // corner to follow: a square fill, a glyph, a blurred shadow.
        //
        // A nine-slice places the corner region of the atlas one for one, so this is the radius the
        // shape keeps at every control size, and it is never more than `corner`.
        radius: f32

        keepBordersRatio = true     // Whether both corner sides shrink together when the destination is too small for them.
    }
}

// Maps GUI parts to scalable regions in the theme atlas.
//
// Several parts name the same atlas tile on purpose: a tile is a shape, and the shape of a round
// fill does not change because a toggle rather than a push button asks for it. What each part
// keeps of its own is the nine-slice `corner` and the `radius` it publishes, which is why two
// rects over one tile can still draw two different controls. `theme/widgets.svg` therefore holds
// each shape exactly once; an empty `rect` means the part draws nothing until a theme sheet points
// it somewhere.
struct ThemeImageRects
{
    public
    {
        surfaceWnd_Shadow: ThemeImageRect = {Math.Rectangle{189, 1, 66, 66}, 24, 0}     // Blurred tile of the shadow a surface casts.

        wnd_Border:       ThemeImageRect = {Math.Rectangle{130, 1, 27, 27}, 3, 0}     // Outline of a window.
        wnd_CaptionBk:    ThemeImageRect = {Math.Rectangle{1, 29, 27, 27}, 12, 0}     // Ground of a large window caption.
        wnd_CaptionSmall: ThemeImageRect = {Math.Rectangle{1, 29, 27, 27}, 1, 0}      // Ground of a compact window caption.

        dlg_BtnBar: ThemeImageRect = {Math.Rectangle{29, 29, 27, 27}, 2, 0}     // Ground of the action bar of a dialog.

        btnPush_Normal:         ThemeImageRect = {Math.Rectangle{1, 57, 27, 27}, 7, 6}      // Fill of a push button at rest.
        btnPush_NormalBorder:   ThemeImageRect = {Math.Rectangle{29, 57, 27, 27}, 7, 6}     // Border of a push button at rest.
        btnPush_Hot:            ThemeImageRect = {Math.Rectangle{1, 57, 27, 27}, 7, 6}      // Fill of a push button under the pointer.
        btnPush_HotBorder:      ThemeImageRect = {Math.Rectangle{29, 57, 27, 27}, 7, 6}     // Border of a push button under the pointer.
        btnPush_Pressed:        ThemeImageRect = {Math.Rectangle{1, 57, 27, 27}, 7, 6}      // Fill of a pressed push button.
        btnPush_PressedBorder:  ThemeImageRect = {Math.Rectangle{29, 57, 27, 27}, 7, 6}     // Border of a pressed push button.
        btnPush_Disabled:       ThemeImageRect = {Math.Rectangle{1, 57, 27, 27}, 7, 6}      // Fill of a disabled push button.
        btnPush_DisabledBorder: ThemeImageRect = {Math.Rectangle{29, 57, 27, 27}, 7, 6}     // Border of a disabled push button.

        btnIcon_SquareBk:      ThemeImageRect = {Math.Rectangle{1, 57, 27, 27}, 7, 6}        // Ground of a compact rectangular icon button.
        btnIcon_RoundBk:       ThemeImageRect = {Math.Rectangle{1, 1, 27, 27}, 13, 12.5}     // Ground of a round icon button.
        btnIcon_RoundSquareBk: ThemeImageRect = {Math.Rectangle{1, 57, 27, 27}, 7, 6}        // Ground of a rounded-square icon button.
        btnIcon_CheckedRing:   ThemeImageRect = {Math.Rectangle{29, 57, 27, 27}, 7, 6}       // Faint ring around a checked icon button.

        btnIcon_CheckedBottom:      ThemeImageRect = {Math.Rectangle{1, 281, 27, 27}, 7, 0}       // Rule of a checked icon button marked on its bottom edge.
        btnIcon_CheckedTop:         ThemeImageRect = {Math.Rectangle{29, 281, 27, 27}, 7, 0}      // Rule of a checked icon button marked on its top edge.
        btnIcon_CheckedLeft:        ThemeImageRect = {Math.Rectangle{57, 281, 27, 27}, 7, 0}      // Rule of a checked icon button marked on its left edge.
        btnIcon_CheckedRight:       ThemeImageRect = {Math.Rectangle{85, 281, 27, 27}, 7, 0}      // Rule of a checked icon button marked on its right edge.
        btnIcon_CheckedSquare:      ThemeImageRect = {Math.Rectangle{1, 57, 27, 27}, 7, 6}        // Fill of a checked compact rectangular icon button.
        btnIcon_CheckedRound:       ThemeImageRect = {Math.Rectangle{1, 1, 27, 27}, 13, 12.5}     // Fill of a checked round icon button.
        btnIcon_CheckedRoundSquare: ThemeImageRect = {Math.Rectangle{1, 57, 27, 27}, 7, 6}        // Fill of a checked rounded-square icon button.

        btnCheck_Normal:          ThemeImageRect = {Math.Rectangle{90, 29, 32, 32}, 16, 4}       // Box of an unchecked check box.
        btnCheck_NormalBorder:    ThemeImageRect = {Math.Rectangle{57, 29, 32, 32}, 16, 4}       // Ring of an unchecked check box.
        btnCheck_Undefined:       ThemeImageRect = {Math.Rectangle{90, 29, 32, 32}, 16, 4}       // Box of a check box in the mixed state.
        btnCheck_UndefinedBorder: ThemeImageRect = {Math.Rectangle{57, 29, 32, 32}, 16, 4}       // Ring of a check box in the mixed state.
        btnCheck_UndefinedMark:   ThemeImageRect = {Math.Rectangle{90, 62, 32, 32}, 16, 0}       // Dash of a check box in the mixed state.
        btnCheck_Checked:         ThemeImageRect = {Math.Rectangle{90, 29, 32, 32}, 16, 4}       // Box of a checked check box.
        btnCheck_CheckedBorder:   ThemeImageRect = {Math.Rectangle{57, 29, 32, 32}, 16, 4}       // Ring of a checked check box.
        btnCheck_CheckedMark:     ThemeImageRect = {Math.Rectangle{57, 62, 32, 32}, 0, 0}        // Check mark of a checked check box.

        btnRadio_NormalBorder:  ThemeImageRect = {Math.Rectangle{123, 29, 32, 32}, 16, 11}     // Border of an unselected radio button.
        btnRadio_Normal:        ThemeImageRect = {Math.Rectangle{156, 29, 32, 32}, 16, 11}     // Disc of an unselected radio button.
        btnRadio_CheckedBorder: ThemeImageRect = {Math.Rectangle{123, 29, 32, 32}, 16, 11}     // Border of a selected radio button.
        btnRadio_Checked:       ThemeImageRect = {Math.Rectangle{156, 29, 32, 32}, 16, 11}     // Disc of a selected radio button.
        btnRadio_CheckedMark:   ThemeImageRect = {Math.Rectangle{123, 62, 32, 32}, 16, 4}      // Dot of a selected radio button.

        edit_SquareBk:          ThemeImageRect = {Math.Rectangle{1, 57, 27, 27}, 7, 6}     // Ground of a field.
        edit_SquareBorder:      ThemeImageRect = {Math.Rectangle{29, 57, 27, 27}, 7, 6}    // Hairline ring of a field.
        edit_SquareStrongBorder: ThemeImageRect = {Math.Rectangle{57, 1, 27, 27}, 7, 6}    // Two-pixel ring of a focused field, or of one holding a rejected value.
        edit_RoundBk:      ThemeImageRect = {Math.Rectangle{1, 1, 27, 27}, 13, 12.5}      // Ground of a round field.
        edit_RoundBorder:  ThemeImageRect = {Math.Rectangle{29, 1, 27, 27}, 13, 12.5}     // Border of a round field.
        edit_FlatBk:       ThemeImageRect = {}     // Nothing: a flat field is told apart by the rule under it alone.
        edit_FlatBorder:   ThemeImageRect = {Math.Rectangle{29, 113, 27, 27}, 5, 0}       // Rule under a flat field.

        btnToggle_Bk:     ThemeImageRect = {Math.Rectangle{1, 1, 27, 27}, 13, 12.5}       // Track of a toggle.
        btnToggle_Border: ThemeImageRect = {Math.Rectangle{29, 1, 27, 27}, 13, 12.5}      // Border of the track of a toggle.
        btnToggle_Mark:   ThemeImageRect = {Math.Rectangle{57, 141, 27, 27}, 13, 9.5}     // Knob of a toggle.

        slider_BkLeft:       ThemeImageRect = {Math.Rectangle{1, 169, 27, 27}, 13, 3.3, false}      // Leading end of a horizontal slider track.
        slider_BkMiddle:     ThemeImageRect = {Math.Rectangle{29, 169, 27, 27}, 13, 0, false}       // Middle of a horizontal slider track.
        slider_BkRight:      ThemeImageRect = {Math.Rectangle{57, 169, 27, 27}, 13, 3.3, false}     // Trailing end of a horizontal slider track.
        slider_BkLeftVert:   ThemeImageRect = {Math.Rectangle{1, 309, 27, 27}, 13, 3.3, false}      // Leading end of a vertical slider track.
        slider_BkMiddleVert: ThemeImageRect = {Math.Rectangle{29, 309, 27, 27}, 13, 0, false}       // Middle of a vertical slider track.
        slider_BkRightVert:  ThemeImageRect = {Math.Rectangle{57, 309, 27, 27}, 13, 3.3, false}     // Trailing end of a vertical slider track.
        slider_Mark:         ThemeImageRect = {Math.Rectangle{86, 170, 25, 25}, 12, 12.5}           // Knob of a slider.
        slider_MarkBorder:   ThemeImageRect = {Math.Rectangle{85, 141, 27, 27}, 13, 13}             // Hairline ring of the knob of a slider.
        slider_Step:         ThemeImageRect = {Math.Rectangle{1, 1, 27, 27}, 13, 12.5}              // Tick marking a step of a slider.

        circular_Mark: ThemeImageRect = {Math.Rectangle{57, 141, 27, 27}, 13, 8.5}     // Knob of a circular control.

        tabItem_FlatSelected:       ThemeImageRect = {Math.Rectangle{57, 95, 27, 27}, 5, 0}            // Ground of the selected tab of a flat bar.
        tabItem_RoundSelected:      ThemeImageRect = {Math.Rectangle{57, 197, 27, 27}, 5, 4}           // Ground of the chosen segment of a round bar.
        tabItem_RoundHot:           ThemeImageRect = {Math.Rectangle{57, 197, 27, 27}, 5, 4}           // Ground of a segment of a round bar under the pointer.
        tabItem_ButtonSelected:     ThemeImageRect = {Math.Rectangle{113, 309, 27, 27}, 9, 9}          // Ground of the selected tab of a button bar.
        tabItem_ButtonHot:          ThemeImageRect = {Math.Rectangle{113, 309, 27, 27}, 9, 9}          // Ground of a tab of a button bar under the pointer.
        tabItem_PushButtonSelected: ThemeImageRect = {Math.Rectangle{113, 309, 27, 27}, 13, 11.58}     // Ground of the selected tab of a push-button bar.
        tabItem_PushButtonHot:      ThemeImageRect = {Math.Rectangle{113, 309, 27, 27}, 13, 11.58}     // Ground of a tab of a push-button bar under the pointer.
        tabItem_PushButtonBk:       ThemeImageRect = {Math.Rectangle{113, 309, 27, 27}, 13, 11.58}     // Ground of a tab of a push-button bar at rest.
        tabItem_PushButtonBorder:   ThemeImageRect = {Math.Rectangle{29, 1, 27, 27}, 13, 12.5}         // Border of a tab of a push-button bar.
        tabBar_FlatBk:              ThemeImageRect = {Math.Rectangle{57, 95, 27, 27}, 5, 0}            // Ground of a flat tab bar.
        tabBar_FlatRoundBk:         ThemeImageRect = {Math.Rectangle{57, 253, 27, 27}, 13, 11.5}       // Ground of a flat tab bar with rounded ends.
        tabBar_RoundBk:             ThemeImageRect = {Math.Rectangle{1, 57, 27, 27}, 7, 6}             // Raised frame of a round tab bar, which holds its segments.
        tabView_FlatBk:             ThemeImageRect = {Math.Rectangle{1, 29, 27, 27}, 10, 0}            // Ground of the page of a flat tab control.
        tabView_RoundBk:            ThemeImageRect = {Math.Rectangle{153, 95, 27, 27}, 10, 10}         // Ground of the page of a round tab control.

        menuPopup_Shadow:            ThemeImageRect = {Math.Rectangle{189, 1, 66, 66}, 24, 0}         // Blurred tile of the shadow a popup menu casts.
        menuPopup_Bk:                ThemeImageRect = {Math.Rectangle{1, 197, 27, 27}, 12, 10}        // Ground of a popup menu.
        menuPopup_Border:            ThemeImageRect = {Math.Rectangle{29, 197, 27, 27}, 12, 10.5}     // Border of a popup menu.
        menuPopup_HotBk:             ThemeImageRect = {Math.Rectangle{57, 197, 27, 27}, 12, 4}        // Ground of a popup menu entry under the pointer.
        menuPopup_BarAnchorBk:       ThemeImageRect = {Math.Rectangle{281, 1, 27, 39}, 7, 6}          // Ground of the tab joining a popup menu to its menu bar entry.
        menuPopup_BarAnchorBorder:   ThemeImageRect = {Math.Rectangle{309, 1, 27, 39}, 7, 6.5}        // Border of the tab joining a popup menu to its menu bar entry.
        menuBar_PopupSelectedBk:     ThemeImageRect = {Math.Rectangle{1, 197, 27, 27}, 12, 10}        // Ground of a menu bar entry whose popup is open.
        menuBar_PopupSelectedBorder: ThemeImageRect = {Math.Rectangle{29, 197, 27, 27}, 12, 10.5}     // Border of a menu bar entry whose popup is open.
        menuBar_Bk:                  ThemeImageRect = {Math.Rectangle{1, 29, 27, 27}, 12, 0}          // Ground of a menu bar.
        menuBar_Border:              ThemeImageRect = {}     // Nothing: a menu bar is told apart by its own ground, not by a rule under it.
        menuBar_SelectedBk:          ThemeImageRect = {Math.Rectangle{57, 197, 27, 27}, 12, 4}        // Ground of a menu bar entry under the pointer or selected.
        menuItem_CheckedMark:        ThemeImageRect = {Math.Rectangle{156, 62, 32, 32}, 0, 0}         // Mark of a checked menu entry.

        scrollBar_BkV:    ThemeImageRect = {Math.Rectangle{1, 29, 27, 27}, 0, 0}          // Track of a vertical scroll bar.
        scrollBar_BkH:    ThemeImageRect = {Math.Rectangle{1, 29, 27, 27}, 0, 0}          // Track of a horizontal scroll bar.
        scrollBar_BoxV:   ThemeImageRect = {Math.Rectangle{29, 253, 27, 27}, 10, 7.5}     // Thumb of a vertical scroll bar.
        scrollBar_BoxH:   ThemeImageRect = {Math.Rectangle{29, 253, 27, 27}, 10, 7.5}     // Thumb of a horizontal scroll bar.
        scrollBar_Corner: ThemeImageRect = {Math.Rectangle{1, 29, 27, 27}, 0, 0}          // Corner where a vertical and a horizontal scroll bar meet.

        frameWnd_SmallShadow:    ThemeImageRect = {Math.Rectangle{189, 1, 66, 66}, 24, 0}       // Blurred tile of the compact shadow of a frame.
        frameWnd_SquareBk:       ThemeImageRect = {Math.Rectangle{1, 57, 27, 27}, 7, 6}         // Ground of a frame with the control corner.
        frameWnd_SquareBorder:   ThemeImageRect = {Math.Rectangle{29, 57, 27, 27}, 7, 6}        // Border of a frame with the control corner.
        frameWnd_RoundBk:        ThemeImageRect = {Math.Rectangle{1, 85, 27, 27}, 13, 12}       // Ground of a floating frame.
        frameWnd_RoundBorder:    ThemeImageRect = {Math.Rectangle{29, 85, 27, 27}, 13, 12}      // Border of a floating frame.
        frameWnd_AnchorTop:      ThemeImageRect = {Math.Rectangle{141, 253, 27, 27}, 0, 0}      // Outline of a callout anchor on the top edge of a frame.
        frameWnd_AnchorTopBk:    ThemeImageRect = {Math.Rectangle{141, 281, 27, 27}, 0, 0}      // Ground of a callout anchor on the top edge of a frame.
        frameWnd_AnchorBottom:   ThemeImageRect = {Math.Rectangle{169, 253, 27, 27}, 0, 0}      // Outline of a callout anchor on the bottom edge of a frame.
        frameWnd_AnchorBottomBk: ThemeImageRect = {Math.Rectangle{169, 281, 27, 27}, 0, 0}      // Ground of a callout anchor on the bottom edge of a frame.
        frameWnd_AnchorRight:    ThemeImageRect = {Math.Rectangle{197, 253, 27, 27}, 0, 0}      // Outline of a callout anchor on the right edge of a frame.
        frameWnd_AnchorRightBk:  ThemeImageRect = {Math.Rectangle{197, 281, 27, 27}, 0, 0}      // Ground of a callout anchor on the right edge of a frame.
        frameWnd_AnchorLeft:     ThemeImageRect = {Math.Rectangle{225, 253, 27, 27}, 0, 0}      // Outline of a callout anchor on the left edge of a frame.
        frameWnd_AnchorLeftBk:   ThemeImageRect = {Math.Rectangle{225, 281, 27, 27}, 0, 0}      // Ground of a callout anchor on the left edge of a frame.

        header_FlatBk:  ThemeImageRect = {Math.Rectangle{1, 57, 27, 27}, 7, 6}           // Ground of a flat column header.
        header_RoundBk: ThemeImageRect = {Math.Rectangle{57, 253, 27, 27}, 13, 11.5}     // Ground of a round column header.

        selectionBox_Bk: ThemeImageRect = {Math.Rectangle{57, 197, 27, 27}, 12, 4}     // Ground of a hovered or selected row, entry, or cell.

        splitView_HorzBarBk:    ThemeImageRect = {Math.Rectangle{85, 197, 27, 27}, 0, 0}      // Bar between two side-by-side panes of a splitter.
        splitView_HorzBarHotBk: ThemeImageRect = {Math.Rectangle{113, 197, 27, 27}, 0, 0}     // Same bar under the pointer.
        splitView_VertBarBk:    ThemeImageRect = {Math.Rectangle{85, 225, 27, 27}, 0, 0}      // Bar between two stacked panes of a splitter.
        splitView_VertBarHotBk: ThemeImageRect = {Math.Rectangle{113, 225, 27, 27}, 0, 0}     // Same bar under the pointer.

        progressBar_Bk:     ThemeImageRect = {Math.Rectangle{1, 1, 27, 27}, 13, 12.5}         // Track of a progress bar.
        progressBar_Border: ThemeImageRect = {}     // Nothing: a progress bar is a track and its fill, with no outline.
        progressBar_Mark:   ThemeImageRect = {Math.Rectangle{1, 1, 27, 27}, 13, 12.5}         // Filled part of a progress bar.

        colorPicker_RoundPick:  ThemeImageRect = {Math.Rectangle{141, 169, 27, 27}, 13, 13.5}     // Round marker of the picked color.
        colorPicker_SquarePick: ThemeImageRect = {Math.Rectangle{169, 169, 27, 27}, 13, 7}        // Square marker of the picked color.
        colorPicker_Bk:         ThemeImageRect = {Math.Rectangle{141, 197, 27, 27}, 13, 5}        // Ground of a color picker.
        colorPicker_Border:     ThemeImageRect = {Math.Rectangle{169, 197, 27, 27}, 13, 6}        // Border of a color picker.

        panel_Bk: ThemeImageRect = {Math.Rectangle{1, 85, 27, 27}, 13, 12}     // Four-sided rounded ground of a standalone content panel.
    }
}
