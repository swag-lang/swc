#global public

using Core

// Describes a scalable region in the theme atlas.
struct ThemeImageRect
{
    public
    {
        rect:   Math.Rectangle     // Region of the atlas the part is drawn from, in authored atlas texels.
        corner: f32                // Side of the nine-slice corner regions, in authored atlas texels; zero stretches the whole region.

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
        surfaceWnd_Shadow: ThemeImageRect = {{189, 1, 66, 66}, 24, 0}     // Blurred tile of the shadow a surface casts.

        wnd_Border:       ThemeImageRect = {{130, 1, 27, 27}, 3, 0}     // Outline of a window.
        wnd_CaptionBk:    ThemeImageRect = {{1, 29, 27, 27}, 12, 0}     // Ground of a large window caption.
        wnd_CaptionSmall: ThemeImageRect = {{1, 29, 27, 27}, 1, 0}      // Ground of a compact window caption.

        dlg_BtnBar: ThemeImageRect = {{29, 29, 27, 27}, 2, 0}     // Ground of the action bar of a dialog.

        btnPush_Normal:         ThemeImageRect = {{1, 1, 27, 27}, 13, 12.5}      // Fill of a push button at rest.
        btnPush_NormalBorder:   ThemeImageRect = {{29, 1, 27, 27}, 13, 12.5}     // Border of a push button at rest.
        btnPush_Hot:            ThemeImageRect = {{1, 1, 27, 27}, 13, 12.5}      // Fill of a push button under the pointer.
        btnPush_HotBorder:      ThemeImageRect = {{29, 1, 27, 27}, 13, 12.5}     // Border of a push button under the pointer.
        btnPush_Pressed:        ThemeImageRect = {{1, 1, 27, 27}, 13, 12.5}      // Fill of a pressed push button.
        btnPush_PressedBorder:  ThemeImageRect = {{29, 1, 27, 27}, 13, 12.5}     // Border of a pressed push button.
        btnPush_Disabled:       ThemeImageRect = {{1, 1, 27, 27}, 13, 12.5}      // Fill of a disabled push button.
        btnPush_DisabledBorder: ThemeImageRect = {{29, 1, 27, 27}, 13, 12.5}     // Border of a disabled push button.

        btnIcon_SquareBk:      ThemeImageRect = {{1, 57, 27, 27}, 7, 4}        // Ground of a compact rectangular icon button.
        btnIcon_RoundBk:       ThemeImageRect = {{1, 1, 27, 27}, 13, 12.5}     // Ground of a round icon button.
        btnIcon_RoundSquareBk: ThemeImageRect = {{1, 57, 27, 27}, 7, 4}        // Ground of a rounded-square icon button.

        btnIcon_CheckedBottom:      ThemeImageRect = {{1, 281, 27, 27}, 7, 0}       // Ground of a checked icon button marked on its bottom edge.
        btnIcon_CheckedTop:         ThemeImageRect = {{29, 281, 27, 27}, 7, 0}      // Ground of a checked icon button marked on its top edge.
        btnIcon_CheckedLeft:        ThemeImageRect = {{57, 281, 27, 27}, 7, 0}      // Ground of a checked icon button marked on its left edge.
        btnIcon_CheckedRight:       ThemeImageRect = {{85, 281, 27, 27}, 7, 0}      // Ground of a checked icon button marked on its right edge.
        btnIcon_CheckedSquare:      ThemeImageRect = {{1, 57, 27, 27}, 7, 4}        // Fill of a checked compact rectangular icon button.
        btnIcon_CheckedRound:       ThemeImageRect = {{1, 1, 27, 27}, 13, 12.5}     // Fill of a checked round icon button.
        btnIcon_CheckedRoundSquare: ThemeImageRect = {{1, 57, 27, 27}, 7, 4}        // Fill of a checked rounded-square icon button.

        btnCheck_Normal:          ThemeImageRect = {{90, 29, 32, 32}, 16, 4}       // Box of an unchecked check box.
        btnCheck_NormalBorder:    ThemeImageRect = {{57, 29, 32, 32}, 16, 4}       // Border of an unchecked check box.
        btnCheck_Undefined:       ThemeImageRect = {{90, 29, 32, 32}, 16, 4}       // Box of a check box in the undefined state.
        btnCheck_UndefinedBorder: ThemeImageRect = {{57, 29, 32, 32}, 16, 4}       // Border of a check box in the undefined state.
        btnCheck_UndefinedMark:   ThemeImageRect = {{90, 62, 32, 32}, 16, 2.5}     // Mark of a check box in the undefined state.
        btnCheck_Checked:         ThemeImageRect = {{90, 29, 32, 32}, 16, 4}       // Box of a checked check box.
        btnCheck_CheckedBorder:   ThemeImageRect = {{57, 29, 32, 32}, 16, 4}       // Border of a checked check box.
        btnCheck_CheckedMark:     ThemeImageRect = {{57, 62, 32, 32}, 0, 0}        // Check mark of a checked check box.

        btnRadio_NormalBorder:  ThemeImageRect = {{123, 29, 32, 32}, 16, 11}     // Border of an unselected radio button.
        btnRadio_Normal:        ThemeImageRect = {{156, 29, 32, 32}, 16, 11}     // Disc of an unselected radio button.
        btnRadio_CheckedBorder: ThemeImageRect = {{123, 29, 32, 32}, 16, 11}     // Border of a selected radio button.
        btnRadio_Checked:       ThemeImageRect = {{156, 29, 32, 32}, 16, 11}     // Disc of a selected radio button.
        btnRadio_CheckedMark:   ThemeImageRect = {{123, 62, 32, 32}, 16, 6}      // Dot of a selected radio button.

        edit_SquareBk:     ThemeImageRect = {{1, 57, 27, 27}, 5, 4}         // Ground of a square-cornered field.
        edit_SquareBorder: ThemeImageRect = {{29, 57, 27, 27}, 5, 4}        // Border of a square-cornered field.
        edit_RoundBk:      ThemeImageRect = {{1, 1, 27, 27}, 13, 12.5}      // Ground of a round field.
        edit_RoundBorder:  ThemeImageRect = {{29, 1, 27, 27}, 13, 12.5}     // Border of a round field.
        edit_FlatBk:       ThemeImageRect = {}                              // Nothing: a flat field is told apart by the rule under it alone.
        edit_FlatBorder:   ThemeImageRect = {{29, 113, 27, 27}, 5, 0}       // Rule under a flat field.

        btnToggle_Bk:     ThemeImageRect = {{1, 1, 27, 27}, 13, 12.5}       // Track of a toggle.
        btnToggle_Border: ThemeImageRect = {{29, 1, 27, 27}, 13, 12.5}      // Border of the track of a toggle.
        btnToggle_Mark:   ThemeImageRect = {{57, 141, 27, 27}, 13, 8.5}     // Knob of a toggle.

        slider_BkLeft:       ThemeImageRect = {{1, 169, 27, 27}, 13, 3.3, false}      // Leading end of a horizontal slider track.
        slider_BkMiddle:     ThemeImageRect = {{29, 169, 27, 27}, 13, 0, false}       // Middle of a horizontal slider track.
        slider_BkRight:      ThemeImageRect = {{57, 169, 27, 27}, 13, 3.3, false}     // Trailing end of a horizontal slider track.
        slider_BkLeftVert:   ThemeImageRect = {{1, 309, 27, 27}, 13, 3.3, false}      // Leading end of a vertical slider track.
        slider_BkMiddleVert: ThemeImageRect = {{29, 309, 27, 27}, 13, 0, false}       // Middle of a vertical slider track.
        slider_BkRightVert:  ThemeImageRect = {{57, 309, 27, 27}, 13, 3.3, false}     // Trailing end of a vertical slider track.
        slider_Mark:         ThemeImageRect = {{86, 170, 25, 25}, 12, 12.5}           // Knob of a slider.
        slider_Step:         ThemeImageRect = {{1, 1, 27, 27}, 13, 12.5}              // Tick marking a step of a slider.

        circular_Mark: ThemeImageRect = {{57, 141, 27, 27}, 13, 8.5}     // Knob of a circular control.

        tabItem_FlatSelected:       ThemeImageRect = {{57, 95, 27, 27}, 5, 0}            // Ground of the selected tab of a flat bar.
        tabItem_RoundSelected:      ThemeImageRect = {{85, 95, 39, 25}, 10, 6.7}         // Ground of the selected tab of a round bar.
        tabItem_RoundHot:           ThemeImageRect = {{85, 95, 39, 25}, 10, 6.7}         // Ground of a tab of a round bar under the pointer.
        tabItem_ButtonSelected:     ThemeImageRect = {{113, 309, 27, 27}, 9, 9}          // Ground of the selected tab of a button bar.
        tabItem_ButtonHot:          ThemeImageRect = {{113, 309, 27, 27}, 9, 9}          // Ground of a tab of a button bar under the pointer.
        tabItem_PushButtonSelected: ThemeImageRect = {{113, 309, 27, 27}, 13, 11.58}     // Ground of the selected tab of a push-button bar.
        tabItem_PushButtonHot:      ThemeImageRect = {{113, 309, 27, 27}, 13, 11.58}     // Ground of a tab of a push-button bar under the pointer.
        tabItem_PushButtonBk:       ThemeImageRect = {{113, 309, 27, 27}, 13, 11.58}     // Ground of a tab of a push-button bar at rest.
        tabItem_PushButtonBorder:   ThemeImageRect = {{29, 1, 27, 27}, 13, 12.5}         // Border of a tab of a push-button bar.
        tabBar_FlatBk:              ThemeImageRect = {{57, 95, 27, 27}, 5, 0}            // Ground of a flat tab bar.
        tabBar_FlatRoundBk:         ThemeImageRect = {{57, 253, 27, 27}, 13, 11.5}       // Ground of a flat tab bar with rounded ends.
        tabBar_RoundBk:             ThemeImageRect = {{1, 1, 27, 27}, 9, 9}              // Ground of a round tab bar.
        tabView_FlatBk:             ThemeImageRect = {{1, 29, 27, 27}, 10, 0}            // Ground of the page of a flat tab control.
        tabView_RoundBk:            ThemeImageRect = {{153, 95, 27, 27}, 10, 10}         // Ground of the page of a round tab control.

        menuPopup_Shadow:            ThemeImageRect = {{189, 1, 66, 66}, 24, 0}         // Blurred tile of the shadow a popup menu casts.
        menuPopup_Bk:                ThemeImageRect = {{1, 197, 27, 27}, 12, 10}        // Ground of a popup menu.
        menuPopup_Border:            ThemeImageRect = {{29, 197, 27, 27}, 12, 10.5}     // Border of a popup menu.
        menuPopup_HotBk:             ThemeImageRect = {{57, 197, 27, 27}, 12, 4}        // Ground of a popup menu entry under the pointer.
        menuPopup_BarAnchorBk:       ThemeImageRect = {{281, 1, 27, 39}, 5, 4}          // Ground of the tab joining a popup menu to its menu bar entry.
        menuPopup_BarAnchorBorder:   ThemeImageRect = {{309, 1, 27, 39}, 5, 4.5}        // Border of the tab joining a popup menu to its menu bar entry.
        menuBar_PopupSelectedBk:     ThemeImageRect = {{1, 197, 27, 27}, 12, 10}        // Ground of a menu bar entry whose popup is open.
        menuBar_PopupSelectedBorder: ThemeImageRect = {{29, 197, 27, 27}, 12, 10.5}     // Border of a menu bar entry whose popup is open.
        menuBar_Bk:                  ThemeImageRect = {{1, 29, 27, 27}, 12, 0}          // Ground of a menu bar.
        menuBar_Border:              ThemeImageRect = {}                                // Nothing: a menu bar is told apart by its own ground, not by a rule under it.
        menuBar_SelectedBk:          ThemeImageRect = {{57, 197, 27, 27}, 12, 4}        // Ground of a menu bar entry under the pointer or selected.
        menuItem_CheckedMark:        ThemeImageRect = {{156, 62, 32, 32}, 0, 0}         // Mark of a checked menu entry.

        scrollBar_BkV:    ThemeImageRect = {{1, 29, 27, 27}, 0, 0}          // Track of a vertical scroll bar.
        scrollBar_BkH:    ThemeImageRect = {{1, 29, 27, 27}, 0, 0}          // Track of a horizontal scroll bar.
        scrollBar_BoxV:   ThemeImageRect = {{29, 253, 27, 27}, 10, 7.5}     // Thumb of a vertical scroll bar.
        scrollBar_BoxH:   ThemeImageRect = {{29, 253, 27, 27}, 10, 7.5}     // Thumb of a horizontal scroll bar.
        scrollBar_Corner: ThemeImageRect = {{1, 29, 27, 27}, 0, 0}          // Corner where a vertical and a horizontal scroll bar meet.

        frameWnd_SmallShadow:    ThemeImageRect = {{189, 1, 66, 66}, 24, 0}       // Blurred tile of the compact shadow of a frame.
        frameWnd_SquareBk:       ThemeImageRect = {{1, 57, 27, 27}, 5, 4}         // Ground of a square frame.
        frameWnd_SquareBorder:   ThemeImageRect = {{29, 57, 27, 27}, 5, 4}        // Border of a square frame.
        frameWnd_RoundBk:        ThemeImageRect = {{1, 1, 27, 27}, 13, 12.5}      // Ground of a round frame.
        frameWnd_RoundBorder:    ThemeImageRect = {{29, 1, 27, 27}, 13, 12.5}     // Border of a round frame.
        frameWnd_AnchorTop:      ThemeImageRect = {{141, 253, 27, 27}, 0, 0}      // Outline of a callout anchor on the top edge of a frame.
        frameWnd_AnchorTopBk:    ThemeImageRect = {{141, 281, 27, 27}, 0, 0}      // Ground of a callout anchor on the top edge of a frame.
        frameWnd_AnchorBottom:   ThemeImageRect = {{169, 253, 27, 27}, 0, 0}      // Outline of a callout anchor on the bottom edge of a frame.
        frameWnd_AnchorBottomBk: ThemeImageRect = {{169, 281, 27, 27}, 0, 0}      // Ground of a callout anchor on the bottom edge of a frame.
        frameWnd_AnchorRight:    ThemeImageRect = {{197, 253, 27, 27}, 0, 0}      // Outline of a callout anchor on the right edge of a frame.
        frameWnd_AnchorRightBk:  ThemeImageRect = {{197, 281, 27, 27}, 0, 0}      // Ground of a callout anchor on the right edge of a frame.
        frameWnd_AnchorLeft:     ThemeImageRect = {{225, 253, 27, 27}, 0, 0}      // Outline of a callout anchor on the left edge of a frame.
        frameWnd_AnchorLeftBk:   ThemeImageRect = {{225, 281, 27, 27}, 0, 0}      // Ground of a callout anchor on the left edge of a frame.

        header_FlatBk:  ThemeImageRect = {{1, 57, 27, 27}, 13, 4}          // Ground of a flat column header.
        header_RoundBk: ThemeImageRect = {{57, 253, 27, 27}, 13, 11.5}     // Ground of a round column header.

        selectionBox_Bk: ThemeImageRect = {{57, 197, 27, 27}, 12, 4}     // Ground of a hovered or selected row, entry, or cell.

        splitView_HorzBarBk:    ThemeImageRect = {{85, 197, 27, 27}, 0, 0}      // Bar between two side-by-side panes of a splitter.
        splitView_HorzBarHotBk: ThemeImageRect = {{113, 197, 27, 27}, 0, 0}     // Same bar under the pointer.
        splitView_VertBarBk:    ThemeImageRect = {{85, 225, 27, 27}, 0, 0}      // Bar between two stacked panes of a splitter.
        splitView_VertBarHotBk: ThemeImageRect = {{113, 225, 27, 27}, 0, 0}     // Same bar under the pointer.

        progressBar_Bk:     ThemeImageRect = {{1, 1, 27, 27}, 13, 12.5}         // Track of a progress bar.
        progressBar_Border: ThemeImageRect = {{29, 1, 27, 27}, 13, 12.5}        // Border of a progress bar.
        progressBar_Mark:   ThemeImageRect = {{169, 141, 27, 27}, 13, 9.76}     // Filled part of a progress bar.

        colorPicker_RoundPick:  ThemeImageRect = {{141, 169, 27, 27}, 13, 13.5}     // Round marker of the picked color.
        colorPicker_SquarePick: ThemeImageRect = {{169, 169, 27, 27}, 13, 7}        // Square marker of the picked color.
        colorPicker_Bk:         ThemeImageRect = {{141, 197, 27, 27}, 13, 5}        // Ground of a color picker.
        colorPicker_Border:     ThemeImageRect = {{169, 197, 27, 27}, 13, 6}        // Border of a color picker.

        panel_Bk: ThemeImageRect = {{1, 57, 27, 27}, 7, 7}     // Four-sided rounded ground of a standalone content panel.
    }
}
