#global public

using Core

// Describes a scalable region in the theme atlas.
struct ThemeImageRect
{
    rect:   Math.Rectangle     // Theme atlas region used for rect.
    corner: f32                // Theme atlas region used for corner.

    // Corner the tile draws, in logical pixels, for the parts that have to follow that shape
    // without drawing it — the keyboard-focus ring is one. Zero means the tile has no single
    // corner to follow: a square fill, a glyph, a blurred shadow.
    //
    // A nine-slice places the corner region of the atlas one for one, so this is the radius the
    // shape keeps at every control size, and it is never more than `corner`.
    radius: f32

    keepBordersRatio = true     // Theme atlas region used for keep borders ratio.
}

// Maps GUI parts to scalable regions in the theme atlas.
struct ThemeImageRects
{
    surfaceWnd_Shadow: ThemeImageRect = {{189, 1, 66, 66}, 24, 0}     // Theme atlas region used for surface wnd shadow.

    wnd_Border:       ThemeImageRect = {{130, 1, 27, 27}, 3, 0}     // Theme atlas region used for wnd border.
    wnd_CaptionBk:    ThemeImageRect = {{57, 1, 72, 27}, 12, 0}     // Theme atlas region used for wnd caption bk.
    wnd_CaptionSmall: ThemeImageRect = {{57, 1, 72, 27}, 1, 0}      // Theme atlas region used for wnd caption small.

    dlg_BtnBar: ThemeImageRect = {{29, 29, 27, 27}, 2, 0}     // Theme atlas region used for dlg btn bar.

    btnPush_Normal:         ThemeImageRect = {{1, 1, 27, 27}, 13, 12.5}      // Theme atlas region used for btn push normal.
    btnPush_NormalBorder:   ThemeImageRect = {{29, 1, 27, 27}, 13, 12.5}     // Theme atlas region used for btn push normal border.
    btnPush_Hot:            ThemeImageRect = {{1, 1, 27, 27}, 13, 12.5}      // Theme atlas region used for btn push hot.
    btnPush_HotBorder:      ThemeImageRect = {{29, 1, 27, 27}, 13, 12.5}     // Theme atlas region used for btn push hot border.
    btnPush_Pressed:        ThemeImageRect = {{1, 1, 27, 27}, 13, 12.5}      // Theme atlas region used for btn push pressed.
    btnPush_PressedBorder:  ThemeImageRect = {{29, 1, 27, 27}, 13, 12.5}     // Theme atlas region used for btn push pressed border.
    btnPush_Disabled:       ThemeImageRect = {{1, 1, 27, 27}, 13, 12.5}      // Theme atlas region used for btn push disabled.
    btnPush_DisabledBorder: ThemeImageRect = {{29, 1, 27, 27}, 13, 12.5}     // Theme atlas region used for btn push disabled border.

    btnIcon_SquareBk:      ThemeImageRect = {{1, 29, 27, 27}, 9, 0}        // Theme atlas region used for btn icon square bk.
    btnIcon_RoundBk:       ThemeImageRect = {{85, 141, 27, 27}, 13, 12.5}     // Theme atlas region used for btn icon round bk.
    btnIcon_RoundSquareBk: ThemeImageRect = {{141, 225, 27, 27}, 7, 4}     // Theme atlas region used for btn icon round square bk.

    btnIcon_CheckedBottom:      ThemeImageRect = {{1, 281, 27, 27}, 7, 0}        // Theme atlas region used for btn icon checked bottom.
    btnIcon_CheckedTop:         ThemeImageRect = {{29, 281, 27, 27}, 7, 0}       // Theme atlas region used for btn icon checked top.
    btnIcon_CheckedLeft:        ThemeImageRect = {{57, 281, 27, 27}, 7, 0}       // Theme atlas region used for btn icon checked left.
    btnIcon_CheckedRight:       ThemeImageRect = {{85, 281, 27, 27}, 7, 0}       // Theme atlas region used for btn icon checked right.
    btnIcon_CheckedSquare:      ThemeImageRect = {{169, 309, 27, 27}, 9, 0}      // Theme atlas region used for btn icon checked square.
    btnIcon_CheckedRound:       ThemeImageRect = {{197, 309, 27, 27}, 13, 12.5}     // Theme atlas region used for btn icon checked round.
    btnIcon_CheckedRoundSquare: ThemeImageRect = {{225, 309, 27, 27}, 7, 4}      // Theme atlas region used for btn icon checked round square.

    btnIcon_ArrowDown:  ThemeImageRect = {{1, 337, 27, 27}, 0, 0}      // Theme atlas region used for btn icon arrow down.
    btnIcon_ArrowLeft:  ThemeImageRect = {{29, 337, 27, 27}, 0, 0}     // Theme atlas region used for btn icon arrow left.
    btnIcon_ArrowUp:    ThemeImageRect = {{57, 337, 27, 27}, 0, 0}     // Theme atlas region used for btn icon arrow up.
    btnIcon_ArrowRight: ThemeImageRect = {{85, 337, 27, 27}, 0, 0}     // Theme atlas region used for btn icon arrow right.

    btnCheck_Normal:          ThemeImageRect = {{90, 29, 32, 32}, 16, 4}     // Theme atlas region used for btn check normal.
    btnCheck_NormalBorder:    ThemeImageRect = {{57, 29, 32, 32}, 16, 4}     // Theme atlas region used for btn check normal border.
    btnCheck_Undefined:       ThemeImageRect = {{90, 29, 32, 32}, 16, 4}     // Theme atlas region used for btn check undefined.
    btnCheck_UndefinedBorder: ThemeImageRect = {{57, 29, 32, 32}, 16, 4}     // Theme atlas region used for btn check undefined border.
    btnCheck_UndefinedMark:   ThemeImageRect = {{90, 62, 32, 32}, 16, 2.5}     // Theme atlas region used for btn check undefined mark.
    btnCheck_Checked:         ThemeImageRect = {{90, 29, 32, 32}, 16, 4}     // Theme atlas region used for btn check checked.
    btnCheck_CheckedBorder:   ThemeImageRect = {{57, 29, 32, 32}, 16, 4}     // Theme atlas region used for btn check checked border.
    btnCheck_CheckedMark:     ThemeImageRect = {{57, 62, 32, 32}, 0, 0}      // Theme atlas region used for btn check checked mark.

    btnRadio_NormalBorder:  ThemeImageRect = {{123, 29, 32, 32}, 16, 11}     // Theme atlas region used for btn radio normal border.
    btnRadio_Normal:        ThemeImageRect = {{156, 29, 32, 32}, 16, 11}     // Theme atlas region used for btn radio normal.
    btnRadio_CheckedBorder: ThemeImageRect = {{123, 29, 32, 32}, 16, 11}     // Theme atlas region used for btn radio checked border.
    btnRadio_Checked:       ThemeImageRect = {{156, 29, 32, 32}, 16, 11}     // Theme atlas region used for btn radio checked.
    btnRadio_CheckedMark:   ThemeImageRect = {{123, 62, 32, 32}, 16, 6}     // Theme atlas region used for btn radio checked mark.

    edit_SquareBk:     ThemeImageRect = {{1, 57, 27, 27}, 5, 4}       // Theme atlas region used for edit square bk.
    edit_SquareBorder: ThemeImageRect = {{29, 57, 27, 27}, 5, 4}      // Theme atlas region used for edit square border.
    edit_RoundBk:      ThemeImageRect = {{1, 85, 27, 27}, 13, 12.5}      // Theme atlas region used for edit round bk.
    edit_RoundBorder:  ThemeImageRect = {{29, 85, 27, 27}, 13, 12.5}     // Theme atlas region used for edit round border.
    edit_FlatBk:       ThemeImageRect = {{1, 113, 27, 27}, 5, 0}      // Theme atlas region used for edit flat bk.
    edit_FlatBorder:   ThemeImageRect = {{29, 113, 27, 27}, 5, 0}     // Theme atlas region used for edit flat border.

    btnToggle_Bk:     ThemeImageRect = {{1, 141, 27, 27}, 13, 12.5}      // Theme atlas region used for btn toggle bk.
    btnToggle_Border: ThemeImageRect = {{29, 141, 27, 27}, 13, 12.5}     // Theme atlas region used for btn toggle border.
    btnToggle_Mark:   ThemeImageRect = {{57, 141, 27, 27}, 13, 8.5}     // Theme atlas region used for btn toggle mark.

    slider_BkLeft:       ThemeImageRect = {{1, 169, 27, 27}, 13, 3.3, false}      // Theme atlas region used for slider bk left.
    slider_BkMiddle:     ThemeImageRect = {{29, 169, 27, 27}, 13, 0, false}     // Theme atlas region used for slider bk middle.
    slider_BkRight:      ThemeImageRect = {{57, 169, 27, 27}, 13, 3.3, false}     // Theme atlas region used for slider bk right.
    slider_BkLeftVert:   ThemeImageRect = {{1, 309, 27, 27}, 13, 3.3, false}      // Theme atlas region used for slider bk left vert.
    slider_BkMiddleVert: ThemeImageRect = {{29, 309, 27, 27}, 13, 0, false}     // Theme atlas region used for slider bk middle vert.
    slider_BkRightVert:  ThemeImageRect = {{57, 309, 27, 27}, 13, 3.3, false}     // Theme atlas region used for slider bk right vert.
    slider_Mark:         ThemeImageRect = {{86, 170, 25, 25}, 12, 12.5}            // Theme atlas region used for slider mark.
    slider_Step:         ThemeImageRect = {{113, 169, 27, 27}, 13, 12.5}           // Theme atlas region used for slider step.

    circular_Mark: ThemeImageRect = {{113, 337, 27, 27}, 13, 8.5}     // Theme atlas region used for circular mark.

    tabItem_FlatSelected:       ThemeImageRect = {{57, 95, 27, 27}, 5, 0}        // Theme atlas region used for tab item flat selected.
    tabItem_RoundSelected:      ThemeImageRect = {{85, 95, 39, 25}, 10, 6.7}       // Theme atlas region used for tab item round selected.
    tabItem_RoundHot:           ThemeImageRect = {{85, 95, 39, 25}, 10, 6.7}       // Theme atlas region used for tab item round hot.
    tabItem_ButtonSelected:     ThemeImageRect = {{113, 309, 27, 27}, 9, 9}      // Theme atlas region used for tab item button selected.
    tabItem_ButtonHot:          ThemeImageRect = {{113, 309, 27, 27}, 9, 9}      // Theme atlas region used for tab item button hot.
    tabItem_PushButtonSelected: ThemeImageRect = {{113, 309, 27, 27}, 13, 11.58}     // Theme atlas region used for tab item push button selected.
    tabItem_PushButtonHot:      ThemeImageRect = {{113, 309, 27, 27}, 13, 11.58}     // Theme atlas region used for tab item push button hot.
    tabItem_PushButtonBk:       ThemeImageRect = {{113, 309, 27, 27}, 13, 11.58}     // Theme atlas region used for tab item push button bk.
    tabItem_PushButtonBorder:   ThemeImageRect = {{141, 309, 27, 27}, 13, 12.5}     // Theme atlas region used for tab item push button border.
    tabBar_FlatBk:              ThemeImageRect = {{57, 95, 27, 27}, 5, 0}        // Theme atlas region used for tab bar flat bk.
    tabBar_FlatRoundBk:         ThemeImageRect = {{57, 253, 27, 27}, 13, 11.5}      // Theme atlas region used for tab bar flat round bk.
    tabBar_RoundBk:             ThemeImageRect = {{85, 309, 27, 27}, 9, 9}       // Theme atlas region used for tab bar round bk.
    tabView_FlatBk:             ThemeImageRect = {{125, 95, 27, 27}, 10, 0}      // Theme atlas region used for tab view flat bk.
    tabView_RoundBk:            ThemeImageRect = {{153, 95, 27, 27}, 10, 10}      // Theme atlas region used for tab view round bk.

    menuPopup_Shadow:            ThemeImageRect = {{189, 1, 66, 66}, 24, 0}      // Theme atlas region used for menu popup shadow.
    menuPopup_Bk:                ThemeImageRect = {{1, 197, 27, 27}, 12, 10}      // Theme atlas region used for menu popup bk.
    menuPopup_Border:            ThemeImageRect = {{29, 197, 27, 27}, 12, 10.5}     // Theme atlas region used for menu popup border.
    menuPopup_HotBk:             ThemeImageRect = {{57, 197, 27, 27}, 12, 4}     // Theme atlas region used for menu popup hot bk.
    menuPopup_BarAnchorBk:       ThemeImageRect = {{281, 1, 27, 39}, 12, 10}      // Theme atlas region used for menu popup bar anchor bk.
    menuPopup_BarAnchorBorder:   ThemeImageRect = {{309, 1, 27, 39}, 12, 10.5}      // Theme atlas region used for menu popup bar anchor border.
    menuBar_PopupSelectedBk:     ThemeImageRect = {{337, 1, 27, 27}, 12, 10}      // Theme atlas region used for menu bar popup selected bk.
    menuBar_PopupSelectedBorder: ThemeImageRect = {{365, 1, 27, 27}, 12, 10.5}      // Theme atlas region used for menu bar popup selected border.
    menuBar_Bk:                  ThemeImageRect = {{1, 225, 27, 27}, 12, 0}      // Theme atlas region used for menu bar bk.
    menuBar_Border:              ThemeImageRect = {{29, 225, 27, 27}, 5, 0}      // Theme atlas region used for menu bar border.
    menuBar_SelectedBk:          ThemeImageRect = {{57, 197, 27, 27}, 12, 4}     // Theme atlas region used for menu bar selected bk.
    menuItem_CheckedMark:        ThemeImageRect = {{156, 62, 32, 32}, 0, 0}      // Theme atlas region used for menu item checked mark.

    scrollBar_BkV:    ThemeImageRect = {{1, 253, 27, 27}, 0, 0}       // Theme atlas region used for scroll bar bk v.
    scrollBar_BkH:    ThemeImageRect = {{1, 253, 27, 27}, 0, 0}       // Theme atlas region used for scroll bar bk h.
    scrollBar_BoxV:   ThemeImageRect = {{29, 253, 27, 27}, 10, 7.5}     // Theme atlas region used for scroll bar box v.
    scrollBar_BoxH:   ThemeImageRect = {{29, 253, 27, 27}, 10, 7.5}     // Theme atlas region used for scroll bar box h.
    scrollBar_Corner: ThemeImageRect = {{1, 253, 27, 27}, 0, 0}       // Theme atlas region used for scroll bar corner.

    frameWnd_SmallShadow:    ThemeImageRect = {{189, 1, 66, 66}, 24, 0}      // Theme atlas region used for frame wnd small shadow.
    frameWnd_SquareBk:       ThemeImageRect = {{1, 57, 27, 27}, 5, 4}        // Theme atlas region used for frame wnd square bk.
    frameWnd_SquareBorder:   ThemeImageRect = {{29, 57, 27, 27}, 5, 4}       // Theme atlas region used for frame wnd square border.
    frameWnd_RoundBk:        ThemeImageRect = {{1, 85, 27, 27}, 13, 12.5}       // Theme atlas region used for frame wnd round bk.
    frameWnd_RoundBorder:    ThemeImageRect = {{29, 85, 27, 27}, 13, 12.5}      // Theme atlas region used for frame wnd round border.
    frameWnd_AnchorTop:      ThemeImageRect = {{141, 253, 27, 27}, 0, 0}     // Theme atlas region used for frame wnd anchor top.
    frameWnd_AnchorTopBk:    ThemeImageRect = {{141, 281, 27, 27}, 0, 0}     // Theme atlas region used for frame wnd anchor top bk.
    frameWnd_AnchorBottom:   ThemeImageRect = {{169, 253, 27, 27}, 0, 0}     // Theme atlas region used for frame wnd anchor bottom.
    frameWnd_AnchorBottomBk: ThemeImageRect = {{169, 281, 27, 27}, 0, 0}     // Theme atlas region used for frame wnd anchor bottom bk.
    frameWnd_AnchorRight:    ThemeImageRect = {{197, 253, 27, 27}, 0, 0}     // Theme atlas region used for frame wnd anchor right.
    frameWnd_AnchorRightBk:  ThemeImageRect = {{197, 281, 27, 27}, 0, 0}     // Theme atlas region used for frame wnd anchor right bk.
    frameWnd_AnchorLeft:     ThemeImageRect = {{225, 253, 27, 27}, 0, 0}     // Theme atlas region used for frame wnd anchor left.
    frameWnd_AnchorLeftBk:   ThemeImageRect = {{225, 281, 27, 27}, 0, 0}     // Theme atlas region used for frame wnd anchor left bk.

    header_FlatBk:  ThemeImageRect = {{57, 225, 27, 27}, 13, 4}     // Theme atlas region used for header flat bk.
    header_RoundBk: ThemeImageRect = {{57, 253, 27, 27}, 13, 11.5}     // Theme atlas region used for header round bk.

    selectionBox_Bk: ThemeImageRect = {{57, 197, 27, 27}, 12, 4}     // Theme atlas region used for selection box bk.

    splitView_HorzBarBk:    ThemeImageRect = {{85, 197, 27, 27}, 0, 0}      // Theme atlas region used for split view horz bar bk.
    splitView_HorzBarHotBk: ThemeImageRect = {{113, 197, 27, 27}, 0, 0}     // Theme atlas region used for split view horz bar hot bk.
    splitView_VertBarBk:    ThemeImageRect = {{85, 225, 27, 27}, 0, 0}      // Theme atlas region used for split view vert bar bk.
    splitView_VertBarHotBk: ThemeImageRect = {{113, 225, 27, 27}, 0, 0}     // Theme atlas region used for split view vert bar hot bk.

    progressBar_Bk:     ThemeImageRect = {{113, 141, 27, 27}, 13, 12.5}     // Theme atlas region used for progress bar bk.
    progressBar_Border: ThemeImageRect = {{141, 141, 27, 27}, 13, 12.5}     // Theme atlas region used for progress bar border.
    progressBar_Mark:   ThemeImageRect = {{169, 141, 27, 27}, 13, 9.76}     // Theme atlas region used for progress bar mark.

    colorPicker_RoundPick:  ThemeImageRect = {{141, 169, 27, 27}, 13, 13.5}     // Theme atlas region used for color picker round pick.
    colorPicker_SquarePick: ThemeImageRect = {{169, 169, 27, 27}, 13, 7}     // Theme atlas region used for color picker square pick.
    colorPicker_Bk:         ThemeImageRect = {{141, 197, 27, 27}, 13, 5}     // Theme atlas region used for color picker bk.
    colorPicker_Border:     ThemeImageRect = {{169, 197, 27, 27}, 13, 6}     // Theme atlas region used for color picker border.
}
