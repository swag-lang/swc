#global public

using Pixel

// Defines the semantic color palette consumed by GUI controls and painters.
//
// One value per painted part. Nothing here is written by hand: every field is derived from
// a [[Gui.ThemePalette]] by [[Gui.ThemeColors.apply]], so a theme answers for every control
// or for none, and the same relationship holds in every theme. A theme that wants one part
// different overrides it afterwards through a theme sheet.
struct ThemeColors
{
    // The three slots rich text addresses with `<p1>`, `<p2>` and `<p3>`.
    richColor1: Color
    richColor2: Color
    richColor3: Color

    // Tint a surface fades to while a modal box holds it. It multiplies the whole surface,
    // so it is a dimming factor rather than a color.
    surfaceDisabled: Color

    bk:     Color     // The application background.
    border: Color     // The rule dividing two blocks of one surface.
    text:   Color     // Primary text.

    hilight:              Color     // The accent, for anything that wants it directly.
    hilightLightContrast: Color     // Ink legible on a fill of the accent.
    activeRail:           Color     // Narrow rule marking active and selected controls, or transparent when unused.
    focusRing:            Color     // Ring drawn around the control the keyboard focus is on.
    error:                Color     // Text and glyphs reporting an operation that stopped.
    disabled:             Color     // Ink and rules of anything the reader cannot act on.
    transparent:          Color     // Nothing drawn. Always zero; named so a sheet can point a part at it.

    // The three strengths of the theme's translucent veil, drawn over whatever is behind
    // them. White over a dark ground, black over a light one.
    veilSoft:   Color
    veilMedium: Color
    veilStrong: Color

    wnd_Bk:                      Color     // Ground of a window body.
    wnd_CaptionBk:               Color     // Caption band of the active window.
    wnd_CaptionBkNotActived:     Color     // Caption band of a window without the focus.
    wnd_CaptionText:             Color     // Title of the active window.
    wnd_CaptionNotActivatedText: Color     // Title of a window without the focus.

    // Outline of a whole surface. It must be opaque: the same stroke runs past the caption
    // ground and the body ground, so a translucent value takes both of them on and the outline
    // visibly changes tone at the caption seam instead of reading as one line.
    wnd_Border: Color

    wnd_BtnCloseBk:          Color     // Ground of a hovered close button.
    wnd_BtnCloseHotBk:       Color     // Ground of a close button under the pointer.
    wnd_BtnCloseHotIcon:     Color     // Glyph of a close button under the pointer.
    wnd_BtnClosePressedIcon: Color     // Glyph of a close button under the press.

    // Ink of the drop shadow. Its alpha is the darkening the shadow reaches where it meets the
    // body, not the alpha of any one ring: the shadow fades from nothing at the outer edge of the
    // margin up to this value against the window.
    wnd_Shadow: Color

    view_Bk: Color     // Ground content is read on.

    dlg_Bk:       Color     // Ground of a dialog.
    dlg_BtnBarBk: Color     // Ground of the button bar of a dialog.

    btnPush_StrongText:   Color     // Label of a filled action.
    btnPush_StrongBorder: Color     // Border of a filled action.
    btnPush_StrongBk:     Color     // Fill of a filled action.

    // A filled action answers the pointer in its own color. Falling back to the neutral
    // hover of a plain button, it lost the accent that made it the primary action of the
    // surface exactly when the reader was about to press it.
    btnPush_StrongHotText:       Color     // Label of a hovered strong button.
    btnPush_StrongHotBorder:     Color     // Border of a hovered strong button.
    btnPush_StrongHotBk:         Color     // Fill of a hovered strong button.
    btnPush_StrongPressedText:   Color     // Label of a pressed strong button.
    btnPush_StrongPressedBorder: Color     // Border of a pressed strong button.
    btnPush_StrongPressedBk:     Color     // Fill of a pressed strong button.

    btnPush_Text:           Color     // Label of a push button.
    btnPush_Border:         Color     // Border of a push button.
    btnPush_Bk:             Color     // Fill of a push button.
    btnPush_PressedText:    Color     // Label of a pressed push button.
    btnPush_PressedBorder:  Color     // Border of a pressed push button.
    btnPush_PressedBk:      Color     // Fill of a pressed push button.
    btnPush_HotText:        Color     // Label of a hovered push button.
    btnPush_HotBorder:      Color     // Border of a hovered push button.
    btnPush_HotBk:          Color     // Fill of a hovered push button.
    btnPush_DisabledText:   Color     // Label of a disabled push button.
    btnPush_DisabledBorder: Color     // Border of a disabled push button.
    btnPush_DisabledBk:     Color     // Fill of a disabled push button.

    btnPushFlat_DisabledText:   Color     // Label of a disabled flat button.
    btnPushFlat_DisabledBorder: Color     // Border of a disabled flat button.
    btnPushFlat_DisabledBk:     Color     // Fill of a disabled flat button.
    btnPushFlat_Text:           Color     // Label of a flat button.
    btnPushFlat_Border:         Color     // Border of a flat button.
    btnPushFlat_Bk:             Color     // Fill of a flat button.
    btnPushFlat_PressedText:    Color     // Label of a pressed flat button.
    btnPushFlat_PressedBorder:  Color     // Border of a pressed flat button.
    btnPushFlat_PressedBk:      Color     // Fill of a pressed flat button.
    btnPushFlat_HotText:        Color     // Label of a hovered flat button.
    btnPushFlat_HotBorder:      Color     // Border of a hovered flat button.
    btnPushFlat_HotBk:          Color     // Fill of a hovered flat button.

    btnPushDefault_DisabledText:   Color     // Label of a disabled default button.
    btnPushDefault_DisabledBorder: Color     // Border of a disabled default button.
    btnPushDefault_DisabledBk:     Color     // Fill of a disabled default button.
    btnPushDefault_Text:           Color     // Label of the default button.
    btnPushDefault_Border:         Color     // Border of the default button.
    btnPushDefault_Bk:             Color     // Fill of the default button.
    btnPushDefault_PressedText:    Color     // Label of the pressed default button.
    btnPushDefault_PressedBorder:  Color     // Border of the pressed default button.
    btnPushDefault_PressedBk:      Color     // Fill of the pressed default button.
    btnPushDefault_HotText:        Color     // Label of the hovered default button.
    btnPushDefault_HotBorder:      Color     // Border of the hovered default button.
    btnPushDefault_HotBk:          Color     // Fill of the hovered default button.

    btnIcon_Icon:         Color     // Glyph of an icon button.
    btnIcon_Text:         Color     // Label of an icon button.
    btnIcon_Bk:           Color     // Fill of an icon button.
    btnIcon_DisabledIcon: Color     // Glyph of a disabled icon button.
    btnIcon_DisabledText: Color     // Label of a disabled icon button.
    btnIcon_DisabledBk:   Color     // Fill of a disabled icon button.
    btnIcon_PressedIcon:  Color     // Glyph of a pressed icon button.
    btnIcon_PressedText:  Color     // Label of a pressed icon button.
    btnIcon_PressedBk:    Color     // Fill of a pressed icon button.
    btnIcon_HotIcon:      Color     // Glyph of a hovered icon button.
    btnIcon_HotText:      Color     // Label of a hovered icon button.
    btnIcon_HotBk:        Color     // Fill of a hovered icon button.

    btnIcon_CheckedDisabledIcon: Color     // Glyph of a checked, disabled icon button.
    btnIcon_CheckedDisabledText: Color     // Label of a checked, disabled icon button.
    btnIcon_CheckedPressedIcon:  Color     // Glyph of a checked, pressed icon button.
    btnIcon_CheckedPressedText:  Color     // Label of a checked, pressed icon button.
    btnIcon_CheckedHotIcon:      Color     // Glyph of a checked, hovered icon button.
    btnIcon_CheckedHotText:      Color     // Label of a checked, hovered icon button.
    btnIcon_CheckedIcon:         Color     // Glyph of a checked icon button.
    btnIcon_CheckedText:         Color     // Label of a checked icon button.
    btnIcon_CheckedDisabledBk:   Color     // Fill of a checked, disabled icon button.
    btnIcon_CheckedPressedBk:    Color     // Fill of a checked, pressed icon button.
    btnIcon_CheckedHotBk:        Color     // Fill of a checked, hovered icon button.
    btnIcon_CheckedBk:           Color     // Fill of a checked icon button.
    btnIcon_CheckedMark:         Color     // Mark saying an icon button is checked.
    btnIcon_CheckedPressedMark:  Color     // Checked mark under the press.
    btnIcon_CheckedHotMark:      Color     // Checked mark under the pointer.
    btnIcon_CheckedDisabledMark: Color     // Checked mark of a disabled button.

    label_Text:         Color     // Primary label text.
    label_TextLight:    Color     // Secondary label text.
    label_TextFaint:    Color     // Counts, status readouts, and other text a reader only glances at.
    label_DisabledText: Color     // Text of a disabled label.
    label_Icon:         Color     // Glyph beside a label.
    label_DisabledIcon: Color     // Glyph beside a disabled label.

    btnCheck_Text:           Color     // Label of a check box.
    btnCheck_Border:         Color     // Border of a check box.
    btnCheck_Mark:           Color     // Mark inside a check box.
    btnCheck_Bk:             Color     // Fill of a check box.
    btnCheck_PressedText:    Color     // Label of a pressed check box.
    btnCheck_PressedBorder:  Color     // Border of a pressed check box.
    btnCheck_PressedMark:    Color     // Mark of a pressed check box.
    btnCheck_PressedBk:      Color     // Fill of a pressed check box.
    btnCheck_HotText:        Color     // Label of a hovered check box.
    btnCheck_HotBorder:      Color     // Border of a hovered check box.
    btnCheck_HotMark:        Color     // Mark of a hovered check box.
    btnCheck_HotBk:          Color     // Fill of a hovered check box.
    btnCheck_DisabledText:   Color     // Label of a disabled check box.
    btnCheck_DisabledBorder: Color     // Border of a disabled check box.
    btnCheck_DisabledMark:   Color     // Mark of a disabled check box.
    btnCheck_DisabledBk:     Color     // Fill of a disabled check box.
    btnCheck_CheckedText:    Color     // Label of a checked box.
    btnCheck_CheckedBk:      Color     // Fill of a checked box.
    btnCheck_CheckedBorder:  Color     // Border of a checked box.
    btnCheck_CheckedMark:    Color     // Mark of a checked box.

    // A tool tip is the inverse of the surface it annotates. It is a transient note rather
    // than a part of the interface, and inverting it is what makes it unmistakable — and
    // legible whatever ground it happens to open over.
    toolTip_Bk:     Color
    toolTip_Border: Color
    toolTip_Text:   Color

    url_Text:    Color     // A link at rest.
    url_HotText: Color     // A link under the pointer.

    edit_Border:         Color     // Border of a field.
    edit_FocusBorder:    Color     // Border of the focused field.
    edit_HotBorder:      Color     // Border of a hovered field.
    edit_DisabledBorder: Color     // Border of a disabled field.
    edit_Bk:             Color     // Fill of a field.
    edit_DisabledBk:     Color     // Fill of a disabled field.
    edit_ErrorBk:        Color     // Fill of a field holding a rejected value.
    edit_HotBk:          Color     // Fill of a hovered field.
    edit_FocusBk:        Color     // Fill of the focused field.
    edit_Note:           Color     // Placeholder note shown while a field is empty.
    edit_Text:           Color     // Text of a field.
    edit_TextUnit:       Color     // Unit written after the value of a field.
    edit_DisabledText:   Color     // Text of a disabled field.
    edit_SelectedBk:     Color     // Ground of selected text.
    edit_ErrorBorder:    Color     // Border of a field holding a rejected value.

    richEdit_Bk:             Color     // Ground of the rich editor.
    richEdit_TextSpecial:    Color     // Marks the editor draws for itself: tabs, ends of line.
    richEdit_Text:           Color     // Text with no style of its own.
    richEdit_SelText:        Color     // Ink of selected text, or transparent to keep each run's own.
    richEdit_SelTextNoFocus: Color     // Ink of selected text while the editor is not focused.
    richEdit_SelBk:          Color     // Ground of selected text.
    richEdit_SelBkNoFocus:   Color     // Ground of selected text while the editor is not focused.
    richEdit_Caret:          Color     // The caret.
    richEdit_CurLineBorder:  Color     // Rule around the line the caret is on.

    btnToggle_DisabledBorder:   Color     // Border of a disabled switch.
    btnToggle_DisabledMark:     Color     // Knob of a disabled switch.
    btnToggle_DisabledBk:       Color     // Track of a disabled switch.
    btnToggle_OffBorder:        Color     // Border of a switch that is off.
    btnToggle_OffMark:          Color     // Knob of a switch that is off.
    btnToggle_OffBk:            Color     // Track of a switch that is off.
    btnToggle_OffHotBorder:     Color     // Border of a hovered switch that is off.
    btnToggle_OffHotMark:       Color     // Knob of a hovered switch that is off.
    btnToggle_OffHotBk:         Color     // Track of a hovered switch that is off.
    btnToggle_OffPressedBorder: Color     // Border of a pressed switch that is off.
    btnToggle_OffPressedMark:   Color     // Knob of a pressed switch that is off.
    btnToggle_OffPressedBk:     Color     // Track of a pressed switch that is off.
    btnToggle_OnBorder:         Color     // Border of a switch that is on.
    btnToggle_OnMark:           Color     // Knob of a switch that is on.
    btnToggle_OnBk:             Color     // Track of a switch that is on.
    btnToggle_OnHotBorder:      Color     // Border of a hovered switch that is on.
    btnToggle_OnHotMark:        Color     // Knob of a hovered switch that is on.
    btnToggle_OnHotBk:          Color     // Track of a hovered switch that is on.
    btnToggle_OnPressedBorder:  Color     // Border of a pressed switch that is on.
    btnToggle_OnPressedMark:    Color     // Knob of a pressed switch that is on.
    btnToggle_OnPressedBk:      Color     // Track of a pressed switch that is on.

    slider_BkLeft:            Color     // Track of a slider, before the thumb.
    slider_BkMiddle:          Color     // Track of a slider, between two thumbs.
    slider_BkRight:           Color     // Track of a slider, after the thumb.
    slider_HilightBk:         Color     // The selected part of the track.
    slider_Mark:              Color     // The thumb.
    slider_HotMark:           Color     // The thumb under the pointer.
    slider_PressedMark:       Color     // The thumb under the press.
    slider_DisabledMark:      Color     // The thumb of a disabled slider.
    slider_DisabledBk:        Color     // Track of a disabled slider.
    slider_DisabledHilightBk: Color     // Selected part of the track of a disabled slider.
    slider_StepBk:            Color     // A step marker on the empty part of the track.
    slider_HilightStepBk:     Color     // A step marker on the selected part of the track.
    slider_HotStepBk:         Color     // A step marker while the slider is hovered.

    circular_Bk:             Color     // Fill inside the dial.
    circular_DisabledBk:     Color     // Fill inside a disabled dial.
    circular_Circle:         Color     // The ring of the dial.
    circular_DisabledCircle: Color     // The ring of a disabled dial.
    circular_Mark:           Color     // The marker on the ring.
    circular_HotMark:        Color     // The marker under the pointer.
    circular_PressedMark:    Color     // The marker under the press.
    circular_DisabledMark:   Color     // The marker of a disabled dial.
    circular_Step:           Color     // A step marker on the ring.
    circular_DisabledStep:   Color     // A step marker on a disabled ring.
    circular_RangeArc:       Color     // The arc between two markers.

    tabItem_SelectedText:             Color     // Label of the selected tab.
    tabItem_HotText:                  Color     // Label of a hovered tab.
    tabItem_Text:                     Color     // Label of a tab at rest.
    tabItem_FlatSelected:             Color     // Ground of the selected flat tab.
    tabItem_FlatHot:                  Color     // Ground of a hovered flat tab.
    tabItem_RoundSelected:            Color     // Ground of the selected round tab.
    tabItem_RoundHot:                 Color     // Ground of a hovered round tab.
    tabItem_ButtonSelected:           Color     // Ground of the selected button tab.
    tabItem_ButtonHot:                Color     // Ground of a hovered button tab.
    tabItem_PushButtonSelected:       Color     // Ground of the selected push-button tab.
    tabItem_PushButtonSelectedText:   Color     // Label of the selected push-button tab.
    tabItem_PushButtonSelectedBorder: Color     // Border of the selected push-button tab.
    tabItem_PushButtonHot:            Color     // Ground of a hovered push-button tab.
    tabItem_PushButtonHotText:        Color     // Label of a hovered push-button tab.
    tabItem_PushButtonHotBorder:      Color     // Border of a hovered push-button tab.
    tabItem_PushButtonText:           Color     // Label of a push-button tab at rest.
    tabItem_PushButtonBk:             Color     // Ground of a push-button tab at rest.
    tabItem_PushButtonBorder:         Color     // Border of a push-button tab at rest.
    tabBar_FlatBk:                    Color     // Ground of a flat tab bar.
    tabBar_RoundBk:                   Color     // Ground of a round tab bar.
    tabView_FlatBk:                   Color     // Ground of the page under a flat tab bar.
    tabView_RoundBk:                  Color     // Ground of the page under a round tab bar.

    menuPopup_Bk:         Color     // Ground of an open menu.
    menuPopup_Border:     Color     // Outline of an open menu.
    menuPopup_Shadow:     Color     // Shadow an open menu casts.
    menuPopup_Separator:  Color     // Rule between two groups of entries.
    menuBar_Bk:           Color     // Ground of a menu bar.
    menuBar_Border:       Color     // Rule under a menu bar.
    menuBar_SelectedBk:   Color     // Ground of the open menu title.
    menuBar_SelectedText: Color     // The open menu title.

    popupItem_Text:         Color     // An entry of a menu.
    popupItem_RightText:    Color     // The shortcut written after an entry.
    popupItem_DisabledText: Color     // An entry the reader cannot choose.
    popupItem_HotText:      Color     // An entry under the pointer.
    popupItem_HotRightText: Color     // The shortcut of an entry under the pointer.
    popupItem_HotBk:        Color     // Ground of an entry under the pointer.

    scrollBar_Bk:         Color     // Track of a scroll bar.
    scrollBar_HotBk:      Color     // Track of a scroll bar under the pointer.
    scrollBar_DisabledBk: Color     // Track of a scroll bar with nothing to scroll.
    scrollBar_Box:        Color     // The thumb.
    scrollBar_HotBox:     Color     // The thumb under the pointer.
    scrollBar_PressedBox: Color     // The thumb under the press.

    comboBox_Border:         Color     // Border of a combo box.
    comboBox_HotBorder:      Color     // Border of a hovered combo box.
    comboBox_DisabledBorder: Color     // Border of a disabled combo box.
    comboBox_SelectedBorder: Color     // Border of a combo box whose list is open.
    comboBox_Bk:             Color     // Fill of a combo box.
    comboBox_HotBk:          Color     // Fill of a hovered combo box.
    comboBox_DisabledBk:     Color     // Fill of a disabled combo box.
    comboBox_SelectedBk:     Color     // Fill of a combo box whose list is open.
    comboBox_Text:           Color     // Text of a combo box.
    comboBox_HotText:        Color     // Text of a hovered combo box.
    comboBox_DisabledText:   Color     // Text of a disabled combo box.
    comboBox_SelectedText:   Color     // Text of a combo box whose list is open.

    popupList_Separator:    Color     // Rule between two groups of a popup list.
    popupList_HotBk:        Color     // Ground of the entry under the pointer.
    popupList_Text:         Color     // An entry of a popup list.
    popupList_HotText:      Color     // The entry under the pointer.
    popupList_CheckMark:    Color     // Mark of a chosen entry.
    popupList_HotCheckMark: Color     // Mark of a chosen entry under the pointer.

    frameWnd_SmallShadow:    Color     // Shadow a framed panel casts.
    frameWnd_Border:         Color     // Outline of a framed panel.
    frameWnd_PopupBorder:    Color     // Outline of a framed panel opened as a popup.
    frameWnd_FocusBorder:    Color     // Outline of a framed panel holding the focus.
    frameWnd_DisabledBorder: Color     // Outline of a disabled framed panel.
    frameWnd_Bk:             Color     // Ground of a framed panel.
    frameWnd_DisabledBk:     Color     // Ground of a disabled framed panel.
    frameWnd_FocusBk:        Color     // Ground of a framed panel holding the focus.

    listItem_FocusSelectedBk:   Color     // Ground of a selected row in the focused list.
    listItem_FocusSelectedText: Color     // Text of a selected row in the focused list.
    listItem_SelectedBk:        Color     // Ground of a selected row.
    listItem_SelectedText:      Color     // Text of a selected row.
    listItem_HotBk:             Color     // Ground of the row under the pointer.
    listItem_DisabledText:      Color     // Text of a row the reader cannot choose.
    listItem_Text:              Color     // Text of a row.
    listItem_Separator:         Color     // Label of a separator row, which carries a group name.
    listItem_AlternateBk:       Color     // Ground of every other row.
    listItem_Line:              Color     // Rule between two rows.

    headerItem_DisabledText: Color     // Label of a disabled column head.
    headerItem_HotText:      Color     // Label of a column head under the pointer.
    headerItem_HotBk:        Color     // Ground of a column head under the pointer.
    headerItem_ClickedBk:    Color     // Ground of a column head under the press.
    headerItem_Text:         Color     // Label of a column head.
    headerItem_Separator:    Color     // Rule between two column heads.
    header_Bk:               Color     // Ground of a header band.

    splitView_TitleBk: Color     // Ground of the title of a split pane.
    splitView_Bar:     Color     // The bar between two panes.
    splitView_BarHot:  Color     // The bar under the pointer.

    progressBar_DisabledBorder: Color     // Border of a disabled progress bar.
    progressBar_DisabledBk:     Color     // Ground of a disabled progress bar.
    progressBar_DisabledMark:   Color     // Filled part of a disabled progress bar.
    progressBar_Border:         Color     // Border of a progress bar.
    progressBar_Bk:             Color     // Ground of a progress bar.
    progressBar_Mark:           Color     // Filled part of a progress bar.

    palPicker_Border:    Color     // Outline of a swatch.
    palPicker_HotBorder: Color     // Outline of a swatch under the pointer.

    colorPicker_Border:    Color     // Outline of the picker surfaces.
    colorPicker_BackAlpha: Color     // Ground shown through a translucent color.
    colorPicker_Mark:      Color     // The marker on a picker surface.

    // Tint a drawn image is multiplied by. White leaves the image alone, which is what an
    // image wants: it carries its own colors and owes the theme nothing.
    imageRect_Fg: Color

    spinner_Dot: Color     // A dot of the waiting ring.

    embInfo_CriticalBk:      Color     // Ground of a notice reporting a failure.
    embInfo_CriticalText:    Color     // Text of a notice reporting a failure.
    embInfo_InformationBk:   Color     // Ground of a notice offering guidance.
    embInfo_InformationText: Color     // Text of a notice offering guidance.
    embInfo_MessageBk:       Color     // Ground of a neutral status notice.
    embInfo_MessageText:     Color     // Text of a neutral status notice.

    prop_FocusBk:     Color     // Ground of the focused row of a property grid.
    prop_FocusBorder: Color     // Outline of the focused row of a property grid.
    prop_HotBk:       Color     // Ground of the row under the pointer.
    prop_HotBorder:   Color     // Outline of the row under the pointer.
    prop_GridBorder:  Color     // Outline of a property grid.
    prop_GridColumn:  Color     // Rule between the name column and the value column.
    prop_SectionBk:   Color     // Ground of a section head.
    prop_CategBk:     Color     // Ground of a category head.
}

impl ThemeColors
{
    // How far a filled action travels under the pointer, and under the press. Enough to
    // be seen, never enough to read as a second color.
    private const StrongHotShift = 0.12'f32
    private const StrongPressedShift = 0.26'f32

    // The three strengths of a veil, as alphas over the palette's veil ink.
    private const VeilSoftAlpha = 0x14'u8
    private const VeilMediumAlpha = 0x24'u8
    private const VeilStrongAlpha = 0x34'u8

    // Ground of alternating rows. Weaker than a soft veil: it must be found, never noticed.
    private const AlternateAlpha = 0x0A'u8

    // The close button is the one control whose meaning does not belong to any theme, so it
    // keeps its own red everywhere. A palette that recolored it would be asking the reader
    // to learn where "close" is on each of its themes.
    private const CloseRed = 0xFFD61425
    private const CloseHotRed = 0xFFE62435
    private const OnCloseRed = 0xFFFFFFFF

    // How far a surface is dimmed while a modal box holds it. A dark surface takes a
    // heavier hand than a light one: the same multiplier that clearly recedes a white page
    // barely registers on near-black.
    private const DimDark = 0xFFBBBBBB
    private const DimLight = 0xFFEEEEEE

    // Moves a fill by `amount` in whichever direction is visible on it.
    //
    // A light fill darkens and a dark one lightens. Always lightening looks obvious until
    // the fill is Voltage, which is already at the top of red and green: mixing it with
    // white can only raise blue, and the button reports nothing the eye can catch.
    private func shiftState(base: Color, amount: f32)->Color
    {
        return base.relativeLuminance() > 0.5 ? Color.darker(base, amount) : Color.lighter(base, amount)
    }

    // Derives the hover and press states of a filled action from the color it is filled
    // with, so a palette declares that color once.
    //
    // The fill lightens under the pointer and darkens under the press, the way a real
    // surface catches and loses light. A button whose three states are the same color
    // reports nothing at the moment the reader is deciding whether to press it.
    private mtd setStrongStates(text, border, bk: Color)
    {
        .btnPush_StrongHotText       = text
        .btnPush_StrongHotBorder     = shiftState(border, StrongHotShift)
        .btnPush_StrongHotBk         = shiftState(bk, StrongHotShift)
        .btnPush_StrongPressedText   = text
        .btnPush_StrongPressedBorder = shiftState(border, StrongPressedShift)
        .btnPush_StrongPressedBk     = shiftState(bk, StrongPressedShift)
    }

    // Derives every semantic color of the theme from `p`.
    //
    // This is the whole rule book, and it is the reason a theme cannot be half written: the
    // palette answers thirty-odd questions and every control is placed by the same
    // relationships, in the same order as the struct above. Read it as the specification of
    // what each part of the interface is allowed to be.
    mtd apply(p: ThemePalette)
    {
        // A filled action travels in its own color, whatever that color is.
        let accentHot     = shiftState(p.accent, StrongHotShift)
        let accentPressed = shiftState(p.accent, StrongPressedShift)

        .richColor1 = p.rich1
        .richColor2 = p.rich2
        .richColor3 = p.rich3

        .surfaceDisabled = p.ground.relativeLuminance() > 0.5 ? Color.fromArgb(DimLight) : Color.fromArgb(DimDark)

        .bk     = p.ground
        .border = p.line
        .text   = p.text

        .hilight              = p.accent
        .hilightLightContrast = p.onAccent
        .activeRail           = p.railed ? p.accent : .transparent
        .focusRing            = p.accent
        .error                = p.error
        .disabled             = p.disabled
        .transparent          = 0

        .veilSoft   = p.veil.withAlpha(VeilSoftAlpha)
        .veilMedium = p.veil.withAlpha(VeilMediumAlpha)
        .veilStrong = p.veil.withAlpha(VeilStrongAlpha)

        .wnd_Bk                      = p.panel
        .wnd_CaptionBk               = p.caption
        .wnd_CaptionBkNotActived     = p.captionInactive
        .wnd_CaptionText             = p.text
        .wnd_CaptionNotActivatedText = p.softText
        .wnd_Border                  = p.windowBorder
        .wnd_BtnCloseBk              = CloseRed
        .wnd_BtnCloseHotBk           = CloseHotRed
        .wnd_BtnCloseHotIcon         = OnCloseRed
        .wnd_BtnClosePressedIcon     = OnCloseRed
        .wnd_Shadow                  = p.shadow

        .view_Bk = p.view

        .dlg_Bk       = p.panel
        .dlg_BtnBarBk = p.view

        .btnPush_StrongText   = p.onAccent
        .btnPush_StrongBorder = p.accent
        .btnPush_StrongBk     = p.accent
        .setStrongStates(p.onAccent, p.accent, p.accent)

        .btnPush_Text           = p.text
        .btnPush_Border         = p.controlLine
        .btnPush_Bk             = p.raised
        .btnPush_PressedText    = p.text
        .btnPush_PressedBorder  = p.accent
        .btnPush_PressedBk      = p.pressed
        .btnPush_HotText        = p.text
        .btnPush_HotBorder      = p.accent
        .btnPush_HotBk          = p.hot
        .btnPush_DisabledText   = p.disabled
        .btnPush_DisabledBorder = p.line
        .btnPush_DisabledBk     = .transparent

        // A flat button is the same button without a resting fill or border: it earns them
        // only once the pointer is on it, which is what keeps a tool bar from reading as a
        // row of boxes.
        .btnPushFlat_Text           = p.text
        .btnPushFlat_Border         = .transparent
        .btnPushFlat_Bk             = .transparent
        .btnPushFlat_PressedText    = p.text
        .btnPushFlat_PressedBorder  = p.accent
        .btnPushFlat_PressedBk      = p.pressed
        .btnPushFlat_HotText        = p.text
        .btnPushFlat_HotBorder      = p.accent
        .btnPushFlat_HotBk          = p.hot
        .btnPushFlat_DisabledText   = p.disabled
        .btnPushFlat_DisabledBorder = .transparent
        .btnPushFlat_DisabledBk     = .transparent

        // The default action and the strong action carry the same accent fill: both are
        // "the thing to do here", one because the keyboard says so and one because the
        // surface does. They differ in weight — a strong button sets its label bold — and
        // a surface is expected to show one or the other, never both.
        .btnPushDefault_Text           = p.onAccent
        .btnPushDefault_Border         = p.accent
        .btnPushDefault_Bk             = p.accent
        .btnPushDefault_PressedText    = p.onAccent
        .btnPushDefault_PressedBorder  = accentPressed
        .btnPushDefault_PressedBk      = accentPressed
        .btnPushDefault_HotText        = p.onAccent
        .btnPushDefault_HotBorder      = accentHot
        .btnPushDefault_HotBk          = accentHot
        .btnPushDefault_DisabledText   = p.disabled
        .btnPushDefault_DisabledBorder = p.line
        .btnPushDefault_DisabledBk     = .transparent

        .btnIcon_Icon         = p.text
        .btnIcon_Text         = p.text
        .btnIcon_Bk           = .transparent
        .btnIcon_DisabledIcon = p.disabled
        .btnIcon_DisabledText = p.disabled
        .btnIcon_DisabledBk   = .transparent
        .btnIcon_PressedIcon  = p.text
        .btnIcon_PressedText  = p.text
        .btnIcon_PressedBk    = p.pressed
        .btnIcon_HotIcon      = p.text
        .btnIcon_HotText      = p.text
        .btnIcon_HotBk        = p.hot

        // A checked tool is marked in one of two ways, and the palette decides which by
        // having a rail or not: a rule in the accent beside the glyph, or — with no rail to
        // draw — the shape of the button filled with the accent. The two want opposite inks.
        // Beside a rule the glyph is the accent itself; over a fill it has to be the ink
        // that fill carries, or a blue glyph disappears into a blue square.
        let checkedInk = p.railed ? p.accent : p.onAccent

        .btnIcon_CheckedIcon         = checkedInk
        .btnIcon_CheckedText         = checkedInk
        .btnIcon_CheckedBk           = .transparent
        .btnIcon_CheckedMark         = p.accent
        .btnIcon_CheckedHotIcon      = checkedInk
        .btnIcon_CheckedHotText      = checkedInk
        .btnIcon_CheckedHotBk        = p.hot
        .btnIcon_CheckedHotMark      = accentHot
        .btnIcon_CheckedPressedIcon  = checkedInk
        .btnIcon_CheckedPressedText  = checkedInk
        .btnIcon_CheckedPressedBk    = p.pressed
        .btnIcon_CheckedPressedMark  = accentPressed
        .btnIcon_CheckedDisabledIcon = p.disabled
        .btnIcon_CheckedDisabledText = p.disabled
        .btnIcon_CheckedDisabledBk   = .transparent

        // The mark of a tool that cannot be picked keeps the shape and loses the accent.
        .btnIcon_CheckedDisabledMark = p.line

        .label_Text         = p.text
        .label_TextLight    = p.softText
        .label_TextFaint    = p.faintText
        .label_DisabledText = p.disabled
        .label_Icon         = p.text
        .label_DisabledIcon = p.disabled

        .btnCheck_Text           = p.text
        .btnCheck_Border         = p.controlLine
        .btnCheck_Mark           = p.text
        .btnCheck_Bk             = .transparent
        .btnCheck_PressedText    = p.text
        .btnCheck_PressedBorder  = p.accent
        .btnCheck_PressedMark    = p.accent
        .btnCheck_PressedBk      = p.pressed
        .btnCheck_HotText        = p.text
        .btnCheck_HotBorder      = p.accent
        .btnCheck_HotMark        = p.accent
        .btnCheck_HotBk          = p.hot
        .btnCheck_DisabledText   = p.disabled
        .btnCheck_DisabledBorder = p.disabled
        .btnCheck_DisabledMark   = p.disabled
        .btnCheck_DisabledBk     = .transparent
        .btnCheck_CheckedText    = p.text
        .btnCheck_CheckedBk      = .transparent
        .btnCheck_CheckedBorder  = p.accent
        .btnCheck_CheckedMark    = p.accent

        .toolTip_Bk     = p.text
        .toolTip_Border = p.text
        .toolTip_Text   = p.ground

        .url_Text    = p.accent
        .url_HotText = accentHot

        .edit_Border         = p.controlLine
        .edit_FocusBorder    = p.accent
        .edit_HotBorder      = p.accent
        .edit_DisabledBorder = p.line
        .edit_Bk             = p.raised
        .edit_DisabledBk     = p.panel
        .edit_ErrorBk        = p.raised
        .edit_HotBk          = p.raised
        .edit_FocusBk        = p.raised
        .edit_Note           = p.faintText
        .edit_Text           = p.text
        .edit_TextUnit       = p.softText
        .edit_DisabledText   = p.disabled
        .edit_SelectedBk     = p.selectPressed
        .edit_ErrorBorder    = p.error

        // Selected code keeps the color its lexer gave it — that is what makes a selection
        // readable in an editor — so the selection is a ground and nothing else.
        .richEdit_Bk             = p.view
        .richEdit_TextSpecial    = p.faintText
        .richEdit_Text           = p.text
        .richEdit_SelText        = .transparent
        .richEdit_SelTextNoFocus = .transparent
        .richEdit_SelBk          = p.selectPressed
        .richEdit_SelBkNoFocus   = p.hot
        .richEdit_Caret          = p.text
        .richEdit_CurLineBorder  = p.line

        .btnToggle_OffBorder        = p.controlLine
        .btnToggle_OffMark          = p.softText
        .btnToggle_OffBk            = .transparent
        .btnToggle_OffHotBorder     = p.accent
        .btnToggle_OffHotMark       = p.text
        .btnToggle_OffHotBk         = p.hot
        .btnToggle_OffPressedBorder = p.accent
        .btnToggle_OffPressedMark   = p.text
        .btnToggle_OffPressedBk     = p.pressed
        .btnToggle_OnBorder         = p.accent
        .btnToggle_OnMark           = p.onAccent
        .btnToggle_OnBk             = p.accent
        .btnToggle_OnHotBorder      = accentHot
        .btnToggle_OnHotMark        = p.onAccent
        .btnToggle_OnHotBk          = accentHot
        .btnToggle_OnPressedBorder  = accentPressed
        .btnToggle_OnPressedMark    = p.onAccent
        .btnToggle_OnPressedBk      = accentPressed
        .btnToggle_DisabledBorder   = p.disabled
        .btnToggle_DisabledMark     = p.disabled
        .btnToggle_DisabledBk       = .transparent

        .slider_BkLeft            = p.pressed
        .slider_BkMiddle          = p.pressed
        .slider_BkRight           = p.pressed
        .slider_HilightBk         = p.accent
        .slider_Mark              = p.accent
        .slider_HotMark           = accentHot
        .slider_PressedMark       = accentPressed
        .slider_DisabledMark      = p.disabled
        .slider_DisabledBk        = p.line
        .slider_DisabledHilightBk = p.disabled
        .slider_StepBk            = p.controlLine
        .slider_HilightStepBk     = p.onAccent
        .slider_HotStepBk         = p.onAccent

        .circular_Bk             = .transparent
        .circular_DisabledBk     = .transparent
        .circular_Circle         = p.controlLine
        .circular_DisabledCircle = p.line
        .circular_Mark           = p.accent
        .circular_HotMark        = accentHot
        .circular_PressedMark    = accentPressed
        .circular_DisabledMark   = p.disabled
        .circular_Step           = p.softText
        .circular_DisabledStep   = p.line
        .circular_RangeArc       = p.accent

        .tabItem_SelectedText             = p.text
        .tabItem_HotText                  = p.text
        .tabItem_Text                     = p.softText
        .tabItem_FlatSelected             = p.selectPressed
        .tabItem_FlatHot                  = p.selectHot
        .tabItem_RoundSelected            = p.selectPressed
        .tabItem_RoundHot                 = p.selectHot
        .tabItem_ButtonSelected           = p.selectPressed
        .tabItem_ButtonHot                = p.selectHot
        .tabItem_PushButtonSelected       = p.selectPressed
        .tabItem_PushButtonSelectedText   = p.text
        .tabItem_PushButtonSelectedBorder = p.accent
        .tabItem_PushButtonHot            = p.selectHot
        .tabItem_PushButtonHotText        = p.text
        .tabItem_PushButtonHotBorder      = p.accent
        .tabItem_PushButtonText           = p.text
        .tabItem_PushButtonBk             = p.raised
        .tabItem_PushButtonBorder         = p.controlLine
        .tabBar_FlatBk                    = p.panel
        .tabBar_RoundBk                   = p.panel
        .tabView_FlatBk                   = p.panel
        .tabView_RoundBk                  = p.panel

        .menuPopup_Bk         = p.panel
        .menuPopup_Border     = p.line
        .menuPopup_Shadow     = p.shadow
        .menuPopup_Separator  = p.line
        .menuBar_Bk           = p.ground
        .menuBar_Border       = p.line
        .menuBar_SelectedBk   = p.selectHot
        .menuBar_SelectedText = p.text

        .popupItem_Text         = p.text
        .popupItem_RightText    = p.softText
        .popupItem_DisabledText = p.disabled
        .popupItem_HotText      = p.text
        .popupItem_HotRightText = p.softText
        .popupItem_HotBk        = p.selectHot

        // A scroll bar is furniture: its track is the ground it sits on until the pointer
        // arrives, and the thumb climbs from faint to full as the reader engages with it.
        .scrollBar_Bk         = p.view
        .scrollBar_HotBk      = .veilSoft
        .scrollBar_DisabledBk = .transparent
        .scrollBar_Box        = p.faintText
        .scrollBar_HotBox     = p.softText
        .scrollBar_PressedBox = p.text

        .comboBox_Border         = p.controlLine
        .comboBox_HotBorder      = p.accent
        .comboBox_DisabledBorder = p.line
        .comboBox_SelectedBorder = p.accent
        .comboBox_Bk             = p.raised
        .comboBox_HotBk          = p.raised
        .comboBox_DisabledBk     = p.panel
        .comboBox_SelectedBk     = p.raised
        .comboBox_Text           = p.text
        .comboBox_HotText        = p.text
        .comboBox_DisabledText   = p.disabled
        .comboBox_SelectedText   = p.text

        .popupList_Separator    = p.line
        .popupList_HotBk        = p.selectHot
        .popupList_Text         = p.text
        .popupList_HotText      = p.text
        .popupList_CheckMark    = p.accent
        .popupList_HotCheckMark = p.accent

        .frameWnd_SmallShadow    = p.shadow.withAlpha(cast(u8) (cast(f32) p.shadow.a * 0.6))
        .frameWnd_Border         = p.line
        .frameWnd_PopupBorder    = p.controlLine
        .frameWnd_FocusBorder    = p.accent
        .frameWnd_DisabledBorder = p.line
        .frameWnd_Bk             = p.panel
        .frameWnd_DisabledBk     = p.panel
        .frameWnd_FocusBk        = p.panel

        .listItem_FocusSelectedBk   = p.selectPressed
        .listItem_FocusSelectedText = p.text
        .listItem_SelectedBk        = p.selectPressed
        .listItem_SelectedText      = p.text
        .listItem_HotBk             = p.selectHot
        .listItem_DisabledText      = p.disabled
        .listItem_Text              = p.text
        .listItem_Separator         = p.faintText
        .listItem_AlternateBk       = p.veil.withAlpha(AlternateAlpha)
        .listItem_Line              = p.line

        .headerItem_DisabledText = p.disabled
        .headerItem_HotText      = p.text
        .headerItem_HotBk        = p.selectHot
        .headerItem_ClickedBk    = p.selectPressed
        .headerItem_Text         = p.text
        .headerItem_Separator    = p.line
        .header_Bk               = p.panel

        .splitView_TitleBk = p.panel
        .splitView_Bar     = p.line
        .splitView_BarHot  = p.accent

        .progressBar_Border         = p.controlLine
        .progressBar_Bk             = p.view
        .progressBar_Mark           = p.accent
        .progressBar_DisabledBorder = p.line
        .progressBar_DisabledBk     = .transparent
        .progressBar_DisabledMark   = p.disabled

        .palPicker_Border    = p.line
        .palPicker_HotBorder = p.accent

        .colorPicker_Border    = p.line
        .colorPicker_BackAlpha = p.panel
        .colorPicker_Mark      = p.text

        .imageRect_Fg = Argb.White

        .spinner_Dot = p.text

        .embInfo_CriticalBk      = p.criticalBk
        .embInfo_CriticalText    = p.criticalText
        .embInfo_InformationBk   = p.infoBk
        .embInfo_InformationText = p.infoText
        .embInfo_MessageBk       = p.noticeBk
        .embInfo_MessageText     = p.noticeText

        .prop_FocusBk     = p.selectPressed
        .prop_FocusBorder = p.accent
        .prop_HotBk       = p.selectHot
        .prop_HotBorder   = .transparent
        .prop_GridBorder  = p.line
        .prop_GridColumn  = p.line
        .prop_SectionBk   = p.view
        .prop_CategBk     = p.view
    }

    // Applies the neutral dark palette: a gray interface on a system blue accent.
    //
    // This is what an application built on the toolkit looks like before it has an identity
    // of its own, so it stays deliberately anonymous.
    mtd setDark()
    {
        .apply(darkPalette())
    }

    // Applies the neutral light palette: the same interface on paper.
    mtd setLight()
    {
        .apply(lightPalette())
    }

    // Applies the dark Swag application palette: Voltage over Ink with neutral structure.
    mtd setSwagDark()
    {
        .apply(swagDarkPalette())
    }

    // Applies the light Swag application palette: Ink over Paper with neutral structure.
    mtd setSwagLight()
    {
        .apply(swagLightPalette())
    }

    // The neutral dark palette.
    func darkPalette()->ThemePalette
    {
        var result: retval

        result.ground  = 0xFF202020
        result.view    = 0xFF282828
        result.panel   = 0xFF353535
        result.raised  = 0xFF353535
        result.hot     = 0xFF3F3F3F
        result.pressed = 0xFF4A4A4A

        // A neutral palette is allowed to wash a row with its accent, because a system blue
        // stays a ground once it is dark enough to write on.
        result.selectHot     = 0xFF1E3A5C
        result.selectPressed = 0xFF27507E

        result.line        = 0xFF404040
        result.controlLine = 0xFF606060

        result.text      = 0xFFE0E0E0
        result.softText  = 0xFF9A9A9A
        result.faintText = 0xFF7C7C7C
        result.disabled  = 0xFF6E6E6E

        result.accent   = 0xFF1473E6
        result.onAccent = 0xFFFFFFFF

        // A neutral theme marks the active item by filling it, so it draws no rail.
        result.railed = false

        result.error        = 0xFFFF6666     // readable on a dark ground, unlike pure red
        result.criticalBk   = 0xFF4A2E2E
        result.criticalText = 0xFFE6ADAD
        result.infoBk       = 0xFF2B3A4C
        result.infoText     = 0xFFAEC8E6
        result.noticeBk     = 0xFF46402A
        result.noticeText   = 0xFFE6D2A2

        result.rich1 = 0xFFF08A8A
        result.rich2 = 0xFF8FD48F
        result.rich3 = 0xFF8FB8F0

        result.veil   = 0xFFFFFFFF
        result.shadow = 0x5A000000

        result.caption         = 0xFF2C2C2C
        result.captionInactive = 0xFF262626
        result.windowBorder    = 0xFF505050

        return result
    }

    // The neutral light palette.
    func lightPalette()->ThemePalette
    {
        var result: retval

        result.ground  = 0xFFF6F6F6
        result.view    = 0xFFFFFFFF
        result.panel   = 0xFFEDEDED
        result.raised  = 0xFFFFFFFF
        result.hot     = 0xFFEFEFEF
        result.pressed = 0xFFE2E2E2

        result.selectHot     = 0xFFE8F2FF
        result.selectPressed = 0xFFD4E7FF

        result.line        = 0xFFDCDCDC
        result.controlLine = 0xFFC2C2C2

        result.text      = 0xFF1F1F1F
        result.softText  = 0xFF5A5A5A
        result.faintText = 0xFF7E7E7E
        result.disabled  = 0xFF9A9A9A

        result.accent   = 0xFF1473E6
        result.onAccent = 0xFFFFFFFF

        result.railed = false

        result.error        = 0xFFC42B2B     // darkened so it stays readable on a light ground
        result.criticalBk   = 0xFFF5DEDE
        result.criticalText = 0xFF9C4A4A
        result.infoBk       = 0xFFDEE7F6
        result.infoText     = 0xFF2E4270
        result.noticeBk     = 0xFFF4EACB
        result.noticeText   = 0xFF7C6636

        result.rich1 = 0xFFB42020
        result.rich2 = 0xFF1E7A32
        result.rich3 = 0xFF1F5AA8

        result.veil   = 0xFF000000
        result.shadow = 0x3C000000

        result.caption         = 0xFFF6F6F6
        result.captionInactive = 0xFFEDEDED
        result.windowBorder    = 0xFFCCCCCC

        return result
    }

    // The dark Swag palette: Voltage over Ink.
    //
    // The accent is the mark's own yellow, which is why nothing here washes a row with it:
    // Voltage is a color to point with, never a color to read on. Hovering and selecting
    // stay neutral and the accent is spent on marks, rails and the one filled action.
    func swagDarkPalette()->ThemePalette
    {
        var result: retval

        result.ground = 0xFF0B0B0D
        result.view   = 0xFF15151A
        result.panel  = 0xFF202026
        result.raised = 0xFF2A2A32

        // Hover has to be seen from across the surface without shouting. A step of nine
        // levels over the raised ground it usually sits on read as nothing at all.
        result.hot     = 0xFF41414E
        result.pressed = 0xFF52525F

        result.selectHot     = result.hot
        result.selectPressed = result.pressed

        result.line        = 0xFF3D3D48
        result.controlLine = 0xFF6B6B77

        result.text      = 0xFFE9E9ED
        result.softText  = 0xFFB4B4BE
        result.faintText = 0xFF91919D
        result.disabled  = 0xFF91919D

        result.accent   = 0xFFF7F900
        result.onAccent = 0xFF0B0B0D

        result.railed = true

        result.error        = 0xFFFF6666
        result.criticalBk   = 0xFF4A2E2E
        result.criticalText = 0xFFE6ADAD
        result.infoBk       = 0xFF2B3A4C
        result.infoText     = 0xFFAEC8E6
        result.noticeBk     = 0xFF46402A
        result.noticeText   = 0xFFE6D2A2

        result.rich1 = 0xFFF08A8A
        result.rich2 = 0xFF8FD48F
        result.rich3 = 0xFF8FB8F0

        result.veil   = 0xFFFFFFFF
        result.shadow = 0x5A000000

        result.caption         = 0xFF2A2A32
        result.captionInactive = 0xFF202026

        // With no drop shadow to cast, the outline is the only thing telling a modal box
        // from the application under it, both cut from the same ink. It stands clearly above
        // the ground without reaching the weight of a control border.
        result.windowBorder = 0xFF5A5A66

        return result
    }

    // The light Swag palette: Ink over Paper.
    //
    // The accent is Ink itself, so the surface has no color at all until something needs
    // pointing at. Everything the dark palette says with Voltage, this one says with black.
    func swagLightPalette()->ThemePalette
    {
        var result: retval

        result.ground  = 0xFFFFFFFF
        result.view    = 0xFFFFFFFF
        result.panel   = 0xFFF7F7F5
        result.raised  = 0xFFFFFFFF
        result.hot     = 0xFFF0F0ED
        result.pressed = 0xFFE7E7E3

        result.selectHot     = result.hot
        result.selectPressed = result.pressed

        result.line        = 0xFFE2E2DF
        result.controlLine = 0xFFCBCBC6

        result.text      = 0xFF1B1B1D
        result.softText  = 0xFF55555C
        result.faintText = 0xFF83838D
        result.disabled  = 0xFF83838D

        result.accent   = 0xFF0B0B0D
        result.onAccent = 0xFFFFFFFF

        result.railed = true

        result.error        = 0xFFC42B2B
        result.criticalBk   = 0xFFF5DEDE
        result.criticalText = 0xFF9C4A4A
        result.infoBk       = 0xFFDEE7F6
        result.infoText     = 0xFF2E4270
        result.noticeBk     = 0xFFF4EACB
        result.noticeText   = 0xFF7C6636

        result.rich1 = 0xFFB42020
        result.rich2 = 0xFF1E7A32
        result.rich3 = 0xFF1F5AA8

        result.veil   = 0xFF000000
        result.shadow = 0x3C000000

        result.caption         = 0xFFFFFFFF
        result.captionInactive = 0xFFF7F7F5
        result.windowBorder    = 0xFFE2E2DF

        return result
    }
}
