#global public

using Pixel

// Defines the semantic color palette consumed by GUI controls and painters.
struct ThemeColors
{
    richColor1: Color     // Semantic color used for rich color1.
    richColor2: Color     // Semantic color used for rich color2.
    richColor3: Color     // Semantic color used for rich color3.

    surfaceDisabled: Color     // Semantic color used for surface disabled.

    bk:     Color     // Semantic color used for bk.
    border: Color     // Semantic color used for border.
    text:   Color     // Semantic color used for text.

    hilight:              Color     // Semantic color used for hilight.
    hilightLight:         Color     // Semantic color used for hilight light.
    hilightDark:          Color     // Semantic color used for hilight dark.
    hilightLightContrast: Color     // Semantic color used for hilight light contrast.
    activeRail:           Color     // Narrow rule marking active and selected controls, or transparent when unused.
    error:                Color     // Text and glyphs reporting an operation that stopped.
    disabled:             Color     // Semantic color used for disabled.
    transparent:          Color     // Semantic color used for transparent.
    lighterSmall:         Color     // Semantic color used for lighter small.
    lighterMedium:        Color     // Semantic color used for lighter medium.
    lighterBig:           Color     // Semantic color used for lighter big.
    lighterVeryBig:       Color     // Semantic color used for lighter very big.

    wnd_Bk:                      Color     // Semantic color used for wnd bk.
    wnd_CaptionBk:               Color     // Semantic color used for wnd caption bk.
    wnd_CaptionBkNotActived:     Color     // Semantic color used for wnd caption bk not actived.
    wnd_CaptionText:             Color     // Semantic color used for wnd caption text.
    wnd_CaptionNotActivatedText: Color     // Semantic color used for wnd caption not activated text.
    wnd_Border:                  Color     // Semantic color used for wnd border.
    wnd_BtnCloseBk:              Color     // Semantic color used for wnd btn close bk.
    wnd_BtnCloseHotBk:           Color     // Semantic color used for wnd btn close hot bk.
    wnd_BtnCloseHotIcon:         Color     // Semantic color used for wnd btn close hot icon.
    wnd_BtnClosePressedIcon:     Color     // Semantic color used for wnd btn close pressed icon.
    wnd_Shadow:                  Color     // Semantic color used for wnd shadow.

    view_Bk: Color     // Semantic color used for view bk.

    dlg_Bk:       Color     // Semantic color used for dlg bk.
    dlg_BtnBarBk: Color     // Semantic color used for dlg btn bar bk.

    btnPush_StrongText:   Color     // Semantic color used for btn push strong text.
    btnPush_StrongBorder: Color     // Semantic color used for btn push strong border.
    btnPush_StrongBk:     Color     // Semantic color used for btn push strong bk.

    btnPush_Text:           Color     // Semantic color used for btn push text.
    btnPush_Border:         Color     // Semantic color used for btn push border.
    btnPush_Bk:             Color     // Semantic color used for btn push bk.
    btnPush_PressedText:    Color     // Semantic color used for btn push pressed text.
    btnPush_PressedBorder:  Color     // Semantic color used for btn push pressed border.
    btnPush_PressedBk:      Color     // Semantic color used for btn push pressed bk.
    btnPush_HotText:        Color     // Semantic color used for btn push hot text.
    btnPush_HotBorder:      Color     // Semantic color used for btn push hot border.
    btnPush_HotBk:          Color     // Semantic color used for btn push hot bk.
    btnPush_DisabledText:   Color     // Semantic color used for btn push disabled text.
    btnPush_DisabledBorder: Color     // Semantic color used for btn push disabled border.
    btnPush_DisabledBk:     Color     // Semantic color used for btn push disabled bk.

    btnPushFlat_DisabledText:   Color     // Semantic color used for btn push flat disabled text.
    btnPushFlat_DisabledBorder: Color     // Semantic color used for btn push flat disabled border.
    btnPushFlat_DisabledBk:     Color     // Semantic color used for btn push flat disabled bk.
    btnPushFlat_Text:           Color     // Semantic color used for btn push flat text.
    btnPushFlat_Border:         Color     // Semantic color used for btn push flat border.
    btnPushFlat_Bk:             Color     // Semantic color used for btn push flat bk.
    btnPushFlat_PressedText:    Color     // Semantic color used for btn push flat pressed text.
    btnPushFlat_PressedBorder:  Color     // Semantic color used for btn push flat pressed border.
    btnPushFlat_PressedBk:      Color     // Semantic color used for btn push flat pressed bk.
    btnPushFlat_HotText:        Color     // Semantic color used for btn push flat hot text.
    btnPushFlat_HotBorder:      Color     // Semantic color used for btn push flat hot border.
    btnPushFlat_HotBk:          Color     // Semantic color used for btn push flat hot bk.

    btnPushDefault_DisabledText:   Color     // Semantic color used for btn push default disabled text.
    btnPushDefault_DisabledBorder: Color     // Semantic color used for btn push default disabled border.
    btnPushDefault_DisabledBk:     Color     // Semantic color used for btn push default disabled bk.
    btnPushDefault_Text:           Color     // Semantic color used for btn push default text.
    btnPushDefault_Border:         Color     // Semantic color used for btn push default border.
    btnPushDefault_Bk:             Color     // Semantic color used for btn push default bk.
    btnPushDefault_PressedText:    Color     // Semantic color used for btn push default pressed text.
    btnPushDefault_PressedBorder:  Color     // Semantic color used for btn push default pressed border.
    btnPushDefault_PressedBk:      Color     // Semantic color used for btn push default pressed bk.
    btnPushDefault_HotText:        Color     // Semantic color used for btn push default hot text.
    btnPushDefault_HotBorder:      Color     // Semantic color used for btn push default hot border.
    btnPushDefault_HotBk:          Color     // Semantic color used for btn push default hot bk.

    btnIcon_Icon:         Color     // Semantic color used for btn icon icon.
    btnIcon_Text:         Color     // Semantic color used for btn icon text.
    btnIcon_Bk:           Color     // Semantic color used for btn icon bk.
    btnIcon_DisabledIcon: Color     // Semantic color used for btn icon disabled icon.
    btnIcon_DisabledText: Color     // Semantic color used for btn icon disabled text.
    btnIcon_DisabledBk:   Color     // Semantic color used for btn icon disabled bk.
    btnIcon_PressedIcon:  Color     // Semantic color used for btn icon pressed icon.
    btnIcon_PressedText:  Color     // Semantic color used for btn icon pressed text.
    btnIcon_PressedBk:    Color     // Semantic color used for btn icon pressed bk.
    btnIcon_HotIcon:      Color     // Semantic color used for btn icon hot icon.
    btnIcon_HotText:      Color     // Semantic color used for btn icon hot text.
    btnIcon_HotBk:        Color     // Semantic color used for btn icon hot bk.

    btnIcon_CheckedDisabledIcon: Color     // Semantic color used for btn icon checked disabled icon.
    btnIcon_CheckedDisabledText: Color     // Semantic color used for btn icon checked disabled text.
    btnIcon_CheckedPressedIcon:  Color     // Semantic color used for btn icon checked pressed icon.
    btnIcon_CheckedPressedText:  Color     // Semantic color used for btn icon checked pressed text.
    btnIcon_CheckedHotIcon:      Color     // Semantic color used for btn icon checked hot icon.
    btnIcon_CheckedHotText:      Color     // Semantic color used for btn icon checked hot text.
    btnIcon_CheckedIcon:         Color     // Semantic color used for btn icon checked icon.
    btnIcon_CheckedText:         Color     // Semantic color used for btn icon checked text.
    btnIcon_CheckedDisabledBk:   Color     // Semantic color used for btn icon checked disabled bk.
    btnIcon_CheckedPressedBk:    Color     // Semantic color used for btn icon checked pressed bk.
    btnIcon_CheckedHotBk:        Color     // Semantic color used for btn icon checked hot bk.
    btnIcon_CheckedBk:           Color     // Semantic color used for btn icon checked bk.
    btnIcon_CheckedMark:         Color     // Semantic color used for btn icon checked mark.
    btnIcon_CheckedPressedMark:  Color     // Semantic color used for btn icon checked pressed mark.
    btnIcon_CheckedHotMark:      Color     // Semantic color used for btn icon checked hot mark.
    btnIcon_CheckedDisabledMark: Color     // Semantic color used for btn icon checked disabled mark.

    label_Text:         Color     // Semantic color used for label text.
    label_TextLight:    Color     // Semantic color used for label text light.
    label_Text1:        Color     // Semantic color used for label text1.
    label_Text2:        Color     // Semantic color used for label text2.
    label_Text3:        Color     // Semantic color used for label text3.
    label_DisabledText: Color     // Semantic color used for label disabled text.
    label_Icon:         Color     // Semantic color used for label icon.
    label_DisabledIcon: Color     // Semantic color used for label disabled icon.

    btnCheck_Text:           Color     // Semantic color used for btn check text.
    btnCheck_Border:         Color     // Semantic color used for btn check border.
    btnCheck_Mark:           Color     // Semantic color used for btn check mark.
    btnCheck_Bk:             Color     // Semantic color used for btn check bk.
    btnCheck_PressedText:    Color     // Semantic color used for btn check pressed text.
    btnCheck_PressedBorder:  Color     // Semantic color used for btn check pressed border.
    btnCheck_PressedMark:    Color     // Semantic color used for btn check pressed mark.
    btnCheck_PressedBk:      Color     // Semantic color used for btn check pressed bk.
    btnCheck_HotText:        Color     // Semantic color used for btn check hot text.
    btnCheck_HotBorder:      Color     // Semantic color used for btn check hot border.
    btnCheck_HotMark:        Color     // Semantic color used for btn check hot mark.
    btnCheck_HotBk:          Color     // Semantic color used for btn check hot bk.
    btnCheck_DisabledText:   Color     // Semantic color used for btn check disabled text.
    btnCheck_DisabledBorder: Color     // Semantic color used for btn check disabled border.
    btnCheck_DisabledMark:   Color     // Semantic color used for btn check disabled mark.
    btnCheck_DisabledBk:     Color     // Semantic color used for btn check disabled bk.
    btnCheck_CheckedText:    Color     // Semantic color used for btn check checked text.
    btnCheck_CheckedBk:      Color     // Semantic color used for btn check checked bk.
    btnCheck_CheckedBorder:  Color     // Semantic color used for btn check checked border.
    btnCheck_CheckedMark:    Color     // Semantic color used for btn check checked mark.

    toolTip_Bk:     Color     // Semantic color used for tool tip bk.
    toolTip_Border: Color     // Semantic color used for tool tip border.
    toolTip_Text:   Color     // Semantic color used for tool tip text.

    url_Text:    Color     // Semantic color used for url text.
    url_HotText: Color     // Semantic color used for url hot text.

    edit_Border:         Color     // Semantic color used for edit border.
    edit_FocusBorder:    Color     // Semantic color used for edit focus border.
    edit_HotBorder:      Color     // Semantic color used for edit hot border.
    edit_DisabledBorder: Color     // Semantic color used for edit disabled border.
    edit_Bk:             Color     // Semantic color used for edit bk.
    edit_DisabledBk:     Color     // Semantic color used for edit disabled bk.
    edit_ErrorBk:        Color     // Semantic color used for edit error bk.
    edit_HotBk:          Color     // Semantic color used for edit hot bk.
    edit_FocusBk:        Color     // Semantic color used for edit focus bk.
    edit_Note:           Color     // Semantic color used for edit note.
    edit_Text:           Color     // Semantic color used for edit text.
    edit_TextUnit:       Color     // Semantic color used for edit text unit.
    edit_DisabledText:   Color     // Semantic color used for edit disabled text.
    edit_SelectedBk:     Color     // Semantic color used for edit selected bk.
    edit_ErrorBorder:    Color     // Semantic color used for edit error border.

    richEdit_Bk:             Color     // Semantic color used for rich edit bk.
    richEdit_TextSpecial:    Color     // Semantic color used for rich edit text special.
    richEdit_Text:           Color     // Semantic color used for rich edit text.
    richEdit_SelText:        Color     // Semantic color used for rich edit sel text.
    richEdit_SelTextNoFocus: Color     // Semantic color used for rich edit sel text no focus.
    richEdit_SelBk:          Color     // Semantic color used for rich edit sel bk.
    richEdit_SelBkNoFocus:   Color     // Semantic color used for rich edit sel bk no focus.
    richEdit_Caret:          Color     // Semantic color used for rich edit caret.
    richEdit_CurLineBorder:  Color     // Semantic color used for rich edit cur line border.

    btnToggle_DisabledBorder:   Color     // Semantic color used for btn toggle disabled border.
    btnToggle_DisabledMark:     Color     // Semantic color used for btn toggle disabled mark.
    btnToggle_DisabledBk:       Color     // Semantic color used for btn toggle disabled bk.
    btnToggle_OffBorder:        Color     // Semantic color used for btn toggle off border.
    btnToggle_OffMark:          Color     // Semantic color used for btn toggle off mark.
    btnToggle_OffBk:            Color     // Semantic color used for btn toggle off bk.
    btnToggle_OffHotBorder:     Color     // Semantic color used for btn toggle off hot border.
    btnToggle_OffHotMark:       Color     // Semantic color used for btn toggle off hot mark.
    btnToggle_OffHotBk:         Color     // Semantic color used for btn toggle off hot bk.
    btnToggle_OffPressedBorder: Color     // Semantic color used for btn toggle off pressed border.
    btnToggle_OffPressedMark:   Color     // Semantic color used for btn toggle off pressed mark.
    btnToggle_OffPressedBk:     Color     // Semantic color used for btn toggle off pressed bk.
    btnToggle_OnBorder:         Color     // Semantic color used for btn toggle on border.
    btnToggle_OnMark:           Color     // Semantic color used for btn toggle on mark.
    btnToggle_OnBk:             Color     // Semantic color used for btn toggle on bk.
    btnToggle_OnHotBorder:      Color     // Semantic color used for btn toggle on hot border.
    btnToggle_OnHotMark:        Color     // Semantic color used for btn toggle on hot mark.
    btnToggle_OnHotBk:          Color     // Semantic color used for btn toggle on hot bk.
    btnToggle_OnPressedBorder:  Color     // Semantic color used for btn toggle on pressed border.
    btnToggle_OnPressedMark:    Color     // Semantic color used for btn toggle on pressed mark.
    btnToggle_OnPressedBk:      Color     // Semantic color used for btn toggle on pressed bk.

    slider_BkLeft:            Color     // Semantic color used for slider bk left.
    slider_BkMiddle:          Color     // Semantic color used for slider bk middle.
    slider_BkRight:           Color     // Semantic color used for slider bk right.
    slider_HilightBk:         Color     // Semantic color used for slider hilight bk.
    slider_Mark:              Color     // Semantic color used for slider mark.
    slider_HotMark:           Color     // Semantic color used for slider hot mark.
    slider_PressedMark:       Color     // Semantic color used for slider pressed mark.
    slider_DisabledMark:      Color     // Semantic color used for slider disabled mark.
    slider_DisabledBk:        Color     // Semantic color used for slider disabled bk.
    slider_DisabledHilightBk: Color     // Semantic color used for slider disabled hilight bk.
    slider_StepBk:            Color     // Semantic color used for slider step bk.
    slider_HilightStepBk:     Color     // Semantic color used for slider hilight step bk.
    slider_HotStepBk:         Color     // Semantic color used for slider hot step bk.

    circular_Bk:             Color     // Semantic color used for circular bk.
    circular_DisabledBk:     Color     // Semantic color used for circular disabled bk.
    circular_Circle:         Color     // Semantic color used for circular circle.
    circular_DisabledCircle: Color     // Semantic color used for circular disabled circle.
    circular_Mark:           Color     // Semantic color used for circular mark.
    circular_HotMark:        Color     // Semantic color used for circular hot mark.
    circular_PressedMark:    Color     // Semantic color used for circular pressed mark.
    circular_DisabledMark:   Color     // Semantic color used for circular disabled mark.
    circular_Step:           Color     // Semantic color used for circular step.
    circular_DisabledStep:   Color     // Semantic color used for circular disabled step.
    circular_RangeArc:       Color     // Semantic color used for circular range arc.

    tabItem_DisabledText:             Color     // Semantic color used for tab item disabled text.
    tabItem_SelectedText:             Color     // Semantic color used for tab item selected text.
    tabItem_HotText:                  Color     // Semantic color used for tab item hot text.
    tabItem_Text:                     Color     // Semantic color used for tab item text.
    tabItem_FlatSelected:             Color     // Semantic color used for tab item flat selected.
    tabItem_FlatHot:                  Color     // Semantic color used for tab item flat hot.
    tabItem_RoundSelected:            Color     // Semantic color used for tab item round selected.
    tabItem_RoundHot:                 Color     // Semantic color used for tab item round hot.
    tabItem_ButtonSelected:           Color     // Semantic color used for tab item button selected.
    tabItem_ButtonHot:                Color     // Semantic color used for tab item button hot.
    tabItem_PushButtonSelected:       Color     // Semantic color used for tab item push button selected.
    tabItem_PushButtonSelectedText:   Color     // Semantic color used for tab item push button selected text.
    tabItem_PushButtonSelectedBorder: Color     // Semantic color used for tab item push button selected border.
    tabItem_PushButtonHot:            Color     // Semantic color used for tab item push button hot.
    tabItem_PushButtonHotText:        Color     // Semantic color used for tab item push button hot text.
    tabItem_PushButtonHotBorder:      Color     // Semantic color used for tab item push button hot border.
    tabItem_PushButtonText:           Color     // Semantic color used for tab item push button text.
    tabItem_PushButtonBk:             Color     // Semantic color used for tab item push button bk.
    tabItem_PushButtonBorder:         Color     // Semantic color used for tab item push button border.
    tabBar_FlatBk:                    Color     // Semantic color used for tab bar flat bk.
    tabBar_RoundBk:                   Color     // Semantic color used for tab bar round bk.
    tabView_FlatBk:                   Color     // Semantic color used for tab view flat bk.
    tabView_RoundBk:                  Color     // Semantic color used for tab view round bk.

    menuPopup_Bk:         Color     // Semantic color used for menu popup bk.
    menuPopup_Border:     Color     // Semantic color used for menu popup border.
    menuPopup_Shadow:     Color     // Semantic color used for menu popup shadow.
    menuPopup_Separator:  Color     // Semantic color used for menu popup separator.
    menuBar_Bk:           Color     // Semantic color used for menu bar bk.
    menuBar_Border:       Color     // Semantic color used for menu bar border.
    menuBar_SelectedBk:   Color     // Semantic color used for menu bar selected bk.
    menuBar_SelectedText: Color     // Semantic color used for menu bar selected text.

    popupItem_Text:         Color     // Semantic color used for popup item text.
    popupItem_RightText:    Color     // Semantic color used for popup item right text.
    popupItem_DisabledText: Color     // Semantic color used for popup item disabled text.
    popupItem_HotText:      Color     // Semantic color used for popup item hot text.
    popupItem_HotRightText: Color     // Semantic color used for popup item hot right text.
    popupItem_HotBk:        Color     // Semantic color used for popup item hot bk.

    scrollBar_Bk:         Color     // Semantic color used for scroll bar bk.
    scrollBar_HotBk:      Color     // Semantic color used for scroll bar hot bk.
    scrollBar_DisabledBk: Color     // Semantic color used for scroll bar disabled bk.
    scrollBar_Box:        Color     // Semantic color used for scroll bar box.
    scrollBar_HotBox:     Color     // Semantic color used for scroll bar hot box.
    scrollBar_PressedBox: Color     // Semantic color used for scroll bar pressed box.

    comboBox_Border:           Color     // Semantic color used for combo box border.
    comboBox_HotBorder:        Color     // Semantic color used for combo box hot border.
    comboBox_DisabledBorder:   Color     // Semantic color used for combo box disabled border.
    comboBox_SelectedBorder:   Color     // Semantic color used for combo box selected border.
    comboBox_Bk:               Color     // Semantic color used for combo box bk.
    comboBox_HotBk:            Color     // Semantic color used for combo box hot bk.
    comboBox_DisabledBk:       Color     // Semantic color used for combo box disabled bk.
    comboBox_SelectedBk:       Color     // Semantic color used for combo box selected bk.
    comboBox_Text:             Color     // Semantic color used for combo box text.
    comboBox_HotText:          Color     // Semantic color used for combo box hot text.
    comboBox_DisabledText:     Color     // Semantic color used for combo box disabled text.
    comboBox_SelectedText:     Color     // Semantic color used for combo box selected text.
    comboBoxItem_Text:         Color     // Semantic color used for combo box item text.
    comboBoxItem_HotBk:        Color     // Semantic color used for combo box item hot bk.
    comboBoxItem_HotText:      Color     // Semantic color used for combo box item hot text.
    comboBoxItem_CheckMark:    Color     // Semantic color used for combo box item check mark.
    comboBoxItem_HotCheckMark: Color     // Semantic color used for combo box item hot check mark.

    popupList_Separator:    Color     // Semantic color used for popup list separator.
    popupList_HotBk:        Color     // Semantic color used for popup list hot bk.
    popupList_Text:         Color     // Semantic color used for popup list text.
    popupList_HotText:      Color     // Semantic color used for popup list hot text.
    popupList_CheckMark:    Color     // Semantic color used for popup list check mark.
    popupList_HotCheckMark: Color     // Semantic color used for popup list hot check mark.

    frameWnd_SmallShadow:    Color     // Semantic color used for frame wnd small shadow.
    frameWnd_Border:         Color     // Semantic color used for frame wnd border.
    frameWnd_PopupBorder:    Color     // Semantic color used for frame wnd popup border.
    frameWnd_FocusBorder:    Color     // Semantic color used for frame wnd focus border.
    frameWnd_DisabledBorder: Color     // Semantic color used for frame wnd disabled border.
    frameWnd_Bk:             Color     // Semantic color used for frame wnd bk.
    frameWnd_DisabledBk:     Color     // Semantic color used for frame wnd disabled bk.
    frameWnd_FocusBk:        Color     // Semantic color used for frame wnd focus bk.

    listItem_FocusSelectedBk:   Color     // Semantic color used for list item focus selected bk.
    listItem_FocusSelectedText: Color     // Semantic color used for list item focus selected text.
    listItem_SelectedBk:        Color     // Semantic color used for list item selected bk.
    listItem_SelectedText:      Color     // Semantic color used for list item selected text.
    listItem_HotBk:             Color     // Semantic color used for list item hot bk.
    listItem_DisabledText:      Color     // Semantic color used for list item disabled text.
    listItem_Text:              Color     // Semantic color used for list item text.
    listItem_Separator:         Color     // Semantic color used for list item separator.
    listItem_AlternateBk:       Color     // Semantic color used for list item alternate bk.
    listItem_Line:              Color     // Semantic color used for list item line.

    headerItem_DisabledText: Color     // Semantic color used for header item disabled text.
    headerItem_HotText:      Color     // Semantic color used for header item hot text.
    headerItem_HotBk:        Color     // Semantic color used for header item hot bk.
    headerItem_ClickedBk:    Color     // Semantic color used for header item clicked bk.
    headerItem_Text:         Color     // Semantic color used for header item text.
    headerItem_Separator:    Color     // Semantic color used for header item separator.
    header_Bk:               Color     // Semantic color used for header bk.

    splitView_TitleBk: Color     // Semantic color used for split view title bk.
    splitView_Bar:     Color     // Semantic color used for split view bar.
    splitView_BarHot:  Color     // Semantic color used for split view bar hot.

    progressBar_DisabledBorder: Color     // Semantic color used for progress bar disabled border.
    progressBar_DisabledBk:     Color     // Semantic color used for progress bar disabled bk.
    progressBar_DisabledMark:   Color     // Semantic color used for progress bar disabled mark.
    progressBar_Border:         Color     // Semantic color used for progress bar border.
    progressBar_Bk:             Color     // Semantic color used for progress bar bk.
    progressBar_Mark:           Color     // Semantic color used for progress bar mark.

    palPicker_Border:    Color     // Semantic color used for pal picker border.
    palPicker_HotBorder: Color     // Semantic color used for pal picker hot border.

    colorPicker_Border:    Color     // Semantic color used for color picker border.
    colorPicker_BackAlpha: Color     // Semantic color used for color picker back alpha.
    colorPicker_Mark:      Color     // Semantic color used for color picker mark.

    imageRect_Fg: Color     // Semantic color used for image rect fg.

    spinner_Dot: Color     // Semantic color used for spinner dot.

    embInfo_CriticalBk:      Color     // Semantic color used for emb info critical bk.
    embInfo_CriticalText:    Color     // Semantic color used for emb info critical text.
    embInfo_InformationBk:   Color     // Semantic color used for emb info information bk.
    embInfo_InformationText: Color     // Semantic color used for emb info information text.
    embInfo_MessageBk:       Color     // Semantic color used for emb info message bk.
    embInfo_MessageText:     Color     // Semantic color used for emb info message text.

    prop_FocusBk:     Color     // Semantic color used for prop focus bk.
    prop_FocusBorder: Color     // Semantic color used for prop focus border.
    prop_HotBk:       Color     // Semantic color used for prop hot bk.
    prop_HotBorder:   Color     // Semantic color used for prop hot border.
    prop_GridBorder:  Color     // Semantic color used for prop grid border.
    prop_GridColumn:  Color     // Semantic color used for prop grid column.
    prop_SectionBk:   Color     // Semantic color used for prop section bk.
    prop_CategBk:     Color     // Semantic color used for prop categ bk.
}

impl ThemeColors
{
    // Sets dark.
    mtd setDark()
    {
        const Transparent    = 0x00000000
        const Blue           = 0xFF1473E6
        const LightBlue      = 0xFF2483F6
        const Error          = 0xFFFF6666     // readable on a dark ground, unlike pure red
        const Disabled       = 0x5FFFFFFF
        const LighterSmall   = 0x0FFFFFFF
        const LighterMedium  = 0x1FFFFFFF
        const LighterBig     = 0x2FFFFFFF
        const LighterVeryBig = 0x3FFFFFFF
        const White          = 0xFFF0F0F0
        const Gray1          = 0xFFE0E0E0
        const Gray2          = 0xFF808080
        const Gray3          = 0xFF606060
        const Gray4          = 0xFF505050
        const Gray5          = 0xFF404040
        const Gray6          = 0xFF353535
        const Gray7          = 0xFF303030
        const Gray8          = 0xFF202020

        .richColor1 = Argb.Red
        .richColor2 = Argb.Green
        .richColor3 = Argb.Blue

        .surfaceDisabled = Color.fromArgb(0xFFBBBBBB)

        .hilight              = Blue
        .hilightLight         = Color.lighter(Color.fromArgb(Blue), 0.2)
        .hilightDark          = Color.darker(Color.fromArgb(Blue), 0.2)
        .hilightLightContrast = Color.contrasting(Color.fromArgb(Blue))
        .activeRail           = Transparent
        .error                = Error
        .disabled             = Disabled
        .transparent          = Transparent
        .lighterSmall         = LighterSmall
        .lighterMedium        = LighterMedium
        .lighterBig           = LighterBig
        .lighterVeryBig       = LighterVeryBig

        .bk     = Gray8
        .border = Gray1
        .text   = Gray1

        .wnd_Bk                      = Gray5
        .wnd_CaptionBk               = Gray4
        .wnd_CaptionBkNotActived     = Gray4
        .wnd_CaptionText             = White
        .wnd_CaptionNotActivatedText = White
        .wnd_Border                  = 0x40FFFFFF
        .wnd_BtnCloseBk              = 0xFFD61425
        .wnd_BtnCloseHotBk           = 0xFFE62435
        .wnd_BtnCloseHotIcon         = White
        .wnd_BtnClosePressedIcon     = White
        .wnd_Shadow                  = 0x70000000

        .view_Bk = 0xFF282828

        .dlg_Bk       = Gray6
        .dlg_BtnBarBk = Gray7

        .btnPush_StrongText   = White
        .btnPush_StrongBorder = White
        .btnPush_StrongBk     = Transparent

        .btnPush_Text           = White
        .btnPush_Border         = Gray2
        .btnPush_Bk             = Transparent
        .btnPush_PressedText    = Gray5
        .btnPush_PressedBorder  = White
        .btnPush_PressedBk      = White
        .btnPush_HotText        = Gray5
        .btnPush_HotBorder      = Gray1
        .btnPush_HotBk          = Gray1
        .btnPush_DisabledText   = Disabled
        .btnPush_DisabledBorder = Disabled
        .btnPush_DisabledBk     = Transparent

        .btnPushFlat_DisabledText   = Disabled
        .btnPushFlat_DisabledBorder = Disabled
        .btnPushFlat_DisabledBk     = Transparent
        .btnPushFlat_Text           = White
        .btnPushFlat_Border         = Transparent
        .btnPushFlat_Bk             = Transparent
        .btnPushFlat_PressedText    = White
        .btnPushFlat_PressedBorder  = Transparent
        .btnPushFlat_PressedBk      = Gray3
        .btnPushFlat_HotText        = White
        .btnPushFlat_HotBorder      = Transparent
        .btnPushFlat_HotBk          = Gray4

        .btnPushDefault_DisabledText   = Disabled
        .btnPushDefault_DisabledBorder = Disabled
        .btnPushDefault_DisabledBk     = Transparent
        .btnPushDefault_Text           = White
        .btnPushDefault_Border         = Blue
        .btnPushDefault_Bk             = Blue
        .btnPushDefault_PressedText    = White
        .btnPushDefault_PressedBorder  = Blue
        .btnPushDefault_PressedBk      = Blue
        .btnPushDefault_HotText        = White
        .btnPushDefault_HotBorder      = LightBlue
        .btnPushDefault_HotBk          = LightBlue

        .btnIcon_Icon         = White
        .btnIcon_Text         = White
        .btnIcon_Bk           = Transparent
        .btnIcon_DisabledIcon = Disabled
        .btnIcon_DisabledText = Disabled
        .btnIcon_DisabledBk   = Transparent
        .btnIcon_PressedIcon  = White
        .btnIcon_PressedText  = White
        .btnIcon_PressedBk    = LighterBig
        .btnIcon_HotIcon      = White
        .btnIcon_HotText      = White
        .btnIcon_HotBk        = LighterMedium

        .btnIcon_CheckedDisabledIcon = Disabled
        .btnIcon_CheckedDisabledText = Disabled
        .btnIcon_CheckedPressedIcon  = White
        .btnIcon_CheckedPressedText  = White
        .btnIcon_CheckedHotIcon      = White
        .btnIcon_CheckedHotText      = White
        .btnIcon_CheckedIcon         = White
        .btnIcon_CheckedText         = White
        .btnIcon_CheckedDisabledBk   = Transparent
        .btnIcon_CheckedPressedBk    = LighterBig
        .btnIcon_CheckedHotBk        = Transparent
        .btnIcon_CheckedBk           = Transparent
        .btnIcon_CheckedMark         = Color.lighter(Color.fromArgb(Blue), 0.2)
        .btnIcon_CheckedPressedMark  = Blue
        .btnIcon_CheckedHotMark      = Color.lighter(Color.fromArgb(Blue), 0.1)
        .btnIcon_CheckedDisabledMark = Disabled

        .label_Text         = Gray1
        .label_TextLight    = Gray2
        .label_Text1        = 0xFFFF5555
        .label_Text2        = 0xFF55FF55
        .label_Text3        = 0xFFFF5555
        .label_DisabledText = Disabled
        .label_Icon         = White
        .label_DisabledIcon = White

        .btnCheck_Text           = White
        .btnCheck_Border         = White
        .btnCheck_Mark           = White
        .btnCheck_Bk             = Transparent
        .btnCheck_PressedText    = White
        .btnCheck_PressedBorder  = White
        .btnCheck_PressedMark    = White
        .btnCheck_PressedBk      = LighterBig
        .btnCheck_HotText        = White
        .btnCheck_HotBorder      = White
        .btnCheck_HotMark        = White
        .btnCheck_HotBk          = LighterSmall
        .btnCheck_DisabledText   = Disabled
        .btnCheck_DisabledBorder = Disabled
        .btnCheck_DisabledMark   = Disabled
        .btnCheck_DisabledBk     = Transparent
        .btnCheck_CheckedText    = White
        .btnCheck_CheckedBk      = Transparent
        .btnCheck_CheckedBorder  = White
        .btnCheck_CheckedMark    = White

        .toolTip_Bk     = 0xFFCCCC88
        .toolTip_Border = 0xFF000000
        .toolTip_Text   = 0xFF222222

        .url_Text    = Blue
        .url_HotText = Color.lighter(Color.fromArgb(Blue), 0.2)

        .edit_Border         = Gray3
        .edit_FocusBorder    = Blue
        .edit_HotBorder      = Gray3
        .edit_DisabledBorder = Gray3
        .edit_Bk             = Gray6
        .edit_DisabledBk     = Gray5
        .edit_ErrorBk        = Gray6
        .edit_HotBk          = Gray6
        .edit_FocusBk        = Gray6
        .edit_Note           = Disabled
        .edit_Text           = White
        .edit_TextUnit       = Disabled
        .edit_DisabledText   = Disabled
        .edit_SelectedBk     = Blue
        .edit_ErrorBorder    = 0xFFFF0000

        .richEdit_Bk             = Gray8
        .richEdit_TextSpecial    = Gray7
        .richEdit_Text           = White
        .richEdit_SelText        = Transparent
        .richEdit_SelTextNoFocus = Transparent
        .richEdit_SelBk          = Color.darker(Color.fromArgb(Blue), 0.5)
        .richEdit_SelBkNoFocus   = Gray6
        .richEdit_Caret          = White
        .richEdit_CurLineBorder  = Gray4

        .btnToggle_DisabledBorder   = Disabled
        .btnToggle_DisabledMark     = Disabled
        .btnToggle_DisabledBk       = Transparent
        .btnToggle_OffBorder        = White
        .btnToggle_OffMark          = White
        .btnToggle_OffBk            = Transparent
        .btnToggle_OffHotBorder     = White
        .btnToggle_OffHotMark       = White
        .btnToggle_OffHotBk         = LighterSmall
        .btnToggle_OffPressedBorder = White
        .btnToggle_OffPressedMark   = White
        .btnToggle_OffPressedBk     = LighterBig
        .btnToggle_OnBorder         = White
        .btnToggle_OnMark           = White
        .btnToggle_OnBk             = Blue
        .btnToggle_OnHotBorder      = White
        .btnToggle_OnHotMark        = White
        .btnToggle_OnHotBk          = LightBlue
        .btnToggle_OnPressedBorder  = White
        .btnToggle_OnPressedMark    = White
        .btnToggle_OnPressedBk      = Blue

        .slider_BkLeft            = Gray4
        .slider_BkMiddle          = Gray4
        .slider_BkRight           = Gray4
        .slider_HilightBk         = Blue
        .slider_Mark              = Blue
        .slider_HotMark           = LightBlue
        .slider_PressedMark       = White
        .slider_DisabledMark      = Gray3
        .slider_DisabledBk        = Gray5
        .slider_DisabledHilightBk = Gray4
        .slider_StepBk            = Gray3
        .slider_HilightStepBk     = LightBlue
        .slider_HotStepBk         = White

        .circular_Bk             = Transparent
        .circular_DisabledBk     = Transparent
        .circular_Circle         = Gray1
        .circular_DisabledCircle = Gray1
        .circular_Mark           = Blue
        .circular_HotMark        = White
        .circular_PressedMark    = White
        .circular_DisabledMark   = Gray4
        .circular_Step           = Gray2
        .circular_DisabledStep   = Gray2
        .circular_RangeArc       = Blue

        .tabItem_DisabledText             = Gray4
        .tabItem_SelectedText             = White
        .tabItem_HotText                  = White
        .tabItem_Text                     = Color.darker(Color.fromArgb(White), 0.3)
        .tabItem_FlatSelected             = Blue
        .tabItem_FlatHot                  = White
        .tabItem_RoundSelected            = Gray6
        .tabItem_RoundHot                 = Gray4
        .tabItem_ButtonSelected           = Gray4
        .tabItem_ButtonHot                = Gray5
        .tabItem_PushButtonSelected       = Blue
        .tabItem_PushButtonSelectedText   = White
        .tabItem_PushButtonSelectedBorder = Blue
        .tabItem_PushButtonHot            = Gray4
        .tabItem_PushButtonHotText        = White
        .tabItem_PushButtonHotBorder      = Blue
        .tabItem_PushButtonText           = Gray1
        .tabItem_PushButtonBk             = Gray6
        .tabItem_PushButtonBorder         = Gray2
        .tabBar_FlatBk                    = Gray4
        .tabBar_RoundBk                   = Gray6
        .tabView_FlatBk                   = Gray6
        .tabView_RoundBk                  = Gray6

        .menuPopup_Bk         = Gray6
        .menuPopup_Border     = Color.lighter(Color.fromArgb(Gray6), 0.2)
        .menuPopup_Shadow     = 0xFF000000
        .menuPopup_Separator  = Color.lighter(Color.fromArgb(Gray6), 0.2)
        .menuBar_Bk           = Gray4
        .menuBar_Border       = 0
        .menuBar_SelectedBk   = 0x1F000000
        .menuBar_SelectedText = Gray1

        .popupItem_Text         = Gray1
        .popupItem_RightText    = Gray2
        .popupItem_DisabledText = Gray2
        .popupItem_HotText      = White
        .popupItem_HotRightText = White
        .popupItem_HotBk        = Blue

        .scrollBar_Bk         = Gray6
        .scrollBar_HotBk      = 0x10888888
        .scrollBar_DisabledBk = 0
        .scrollBar_Box        = Gray3
        .scrollBar_HotBox     = Gray2
        .scrollBar_PressedBox = Gray1

        .comboBox_Border           = Gray3
        .comboBox_HotBorder        = Gray2
        .comboBox_DisabledBorder   = Gray3
        .comboBox_SelectedBorder   = Gray2
        .comboBox_Bk               = Gray6
        .comboBox_HotBk            = Color.darker(Color.fromArgb(Gray5), 0.05)
        .comboBox_DisabledBk       = Gray5
        .comboBox_SelectedBk       = Gray6
        .comboBox_Text             = Gray1
        .comboBox_HotText          = White
        .comboBox_DisabledText     = Gray3
        .comboBox_SelectedText     = White
        .comboBoxItem_Text         = Gray1
        .comboBoxItem_HotBk        = Blue
        .comboBoxItem_HotText      = White
        .comboBoxItem_CheckMark    = Blue
        .comboBoxItem_HotCheckMark = White

        .popupList_Separator    = Gray4
        .popupList_HotBk        = Blue
        .popupList_Text         = Gray1
        .popupList_HotText      = White
        .popupList_CheckMark    = Blue
        .popupList_HotCheckMark = White

        .frameWnd_SmallShadow    = 0x50000000
        .frameWnd_Border         = Gray3
        .frameWnd_PopupBorder    = Gray2
        .frameWnd_FocusBorder    = Blue
        .frameWnd_DisabledBorder = Gray3
        .frameWnd_Bk             = Gray6
        .frameWnd_DisabledBk     = Gray5
        .frameWnd_FocusBk        = Gray6

        .listItem_FocusSelectedBk   = Blue
        .listItem_FocusSelectedText = White
        .listItem_SelectedBk        = Gray5
        .listItem_SelectedText      = Gray1
        .listItem_HotBk             = Gray5
        .listItem_DisabledText      = Gray3
        .listItem_Text              = White
        .listItem_Separator         = Color.darker(Color.fromArgb(White), 0.3)
        .listItem_AlternateBk       = 0x08FFFFFF
        .listItem_Line              = Gray4

        .headerItem_DisabledText = Gray4
        .headerItem_HotText      = White
        .headerItem_HotBk        = 0x10FFFFFF
        .headerItem_ClickedBk    = 0x20FFFFFF
        .headerItem_Text         = White
        .headerItem_Separator    = Color.lighter(Color.fromArgb(Gray4), 0.2)
        .header_Bk               = Gray4

        .splitView_TitleBk = Gray6
        .splitView_Bar     = Gray4
        .splitView_BarHot  = Blue

        .progressBar_DisabledBorder = Gray3
        .progressBar_DisabledBk     = Transparent
        .progressBar_DisabledMark   = Gray3
        .progressBar_Border         = Gray2
        .progressBar_Bk             = Gray6
        .progressBar_Mark           = Blue

        .palPicker_Border    = Gray7
        .palPicker_HotBorder = Blue

        .colorPicker_Border    = 0x3F000000
        .colorPicker_BackAlpha = Gray4
        .colorPicker_Mark      = Gray1

        .imageRect_Fg = White

        .spinner_Dot = Gray1

        // Dark theme: deep, desaturated notice backgrounds with soft, light text — so a chip reads
        // as a muted tint of the dark UI, not a loud light block. Status icons keep native colors.
        .embInfo_CriticalBk      = 0xFF4A2E2E
        .embInfo_CriticalText    = 0xFFE6ADAD
        .embInfo_InformationBk   = 0xFF2B3A4C
        .embInfo_InformationText = 0xFFAEC8E6
        .embInfo_MessageBk       = 0xFF46402A
        .embInfo_MessageText     = 0xFFE6D2A2

        .prop_FocusBk     = Color.lighter(Color.fromArgb(Gray5), 0.05)
        .prop_FocusBorder = Gray3
        .prop_HotBk       = Color.darker(Color.fromArgb(Gray5), 0.03)
        .prop_HotBorder   = Transparent
        .prop_GridBorder  = Gray7
        .prop_GridColumn  = Gray7
        .prop_SectionBk   = Gray6
        .prop_CategBk     = Gray6
    }

    // Sets light.
    mtd setLight()
    {
        const Transparent      = 0x00000000
        const Blue             = 0xFF1473E6
        const LightBlue        = 0xFF2483F6
        const Error            = 0xFFC42B2B     // darkened so it stays readable on a light ground
        const Disabled         = 0x5F000000
        const DisabledBorder   = 0xFFDCDCDC     // weaker than the normal control border (Gray6)
        const LighterSmall     = 0x10888888
        const LighterMedium    = 0x20888888
        const LighterBig       = 0x30888888
        const LighterVeryBig   = 0x40888888
        const White            = 0xFFFFFFFF
        const Gray1            = 0xFF505050     // primary text
        const Gray2            = 0xFF606060     // secondary text
        const Gray3            = 0xFF707070     // muted text / strong borders
        const Gray4            = 0xFF808080     // subtle icons / secondary borders
        const Gray5            = 0xFFA0A0A0     // disabled-ish strokes
        const Gray6            = 0xFFCCCCCC     // control borders
        const Gray7            = 0xFFE6E6E6     // panel fills
        const Gray8            = 0xFFF6F6F6     // app background / views
        const NeutralHotBk     = 0xFFEFEFEF
        const NeutralPressedBk = 0xFFE2E2E2
        const AccentHotBk      = 0xFFE8F2FF
        const AccentPressedBk  = 0xFFD4E7FF

        .richColor1 = Argb.Red
        .richColor2 = Argb.Green
        .richColor3 = Argb.Blue

        .surfaceDisabled = Color.fromArgb(0xFFEEEEEE)

        .hilight              = Blue
        .hilightLight         = Color.lighter(Color.fromArgb(Blue), 0.2)
        .hilightDark          = Color.darker(Color.fromArgb(Blue), 0.2)
        .hilightLightContrast = Color.contrasting(Color.fromArgb(Blue))
        .activeRail           = Transparent
        .error                = Error
        .disabled             = Disabled
        .transparent          = Transparent
        .lighterSmall         = LighterSmall
        .lighterMedium        = LighterMedium
        .lighterBig           = LighterBig
        .lighterVeryBig       = LighterVeryBig

        .bk     = Gray8
        .border = Gray1
        .text   = Gray1

        .wnd_Bk                      = Gray8
        .wnd_CaptionBk               = Gray8
        .wnd_CaptionBkNotActived     = Gray8
        .wnd_CaptionText             = Gray1
        .wnd_CaptionNotActivatedText = Gray2
        .wnd_Border                  = 0x26000000
        .wnd_BtnCloseBk              = 0xFFD61425
        .wnd_BtnCloseHotBk           = 0xFFE62435
        .wnd_BtnCloseHotIcon         = White
        .wnd_BtnClosePressedIcon     = White
        .wnd_Shadow                  = 0x44000000

        .view_Bk = White

        .dlg_Bk       = Gray7
        .dlg_BtnBarBk = Gray7

        .btnPush_StrongText   = Gray1
        .btnPush_StrongBorder = Gray1
        .btnPush_StrongBk     = Transparent

        .btnPush_Text           = Gray1
        .btnPush_Border         = Gray6
        .btnPush_Bk             = Transparent
        .btnPush_PressedText    = Gray1
        .btnPush_PressedBorder  = Blue
        .btnPush_PressedBk      = AccentPressedBk
        .btnPush_HotText        = Gray1
        .btnPush_HotBorder      = Blue
        .btnPush_HotBk          = AccentHotBk
        .btnPush_DisabledText   = Disabled
        .btnPush_DisabledBorder = DisabledBorder
        .btnPush_DisabledBk     = Transparent

        .btnPushFlat_DisabledText   = Disabled
        .btnPushFlat_DisabledBorder = DisabledBorder
        .btnPushFlat_DisabledBk     = Transparent
        .btnPushFlat_Text           = Gray1
        .btnPushFlat_Border         = Transparent
        .btnPushFlat_Bk             = Transparent
        .btnPushFlat_PressedText    = Gray1
        .btnPushFlat_PressedBorder  = Blue
        .btnPushFlat_PressedBk      = AccentPressedBk
        .btnPushFlat_HotText        = Gray1
        .btnPushFlat_HotBorder      = Blue
        .btnPushFlat_HotBk          = AccentHotBk

        .btnPushDefault_DisabledText   = Disabled
        .btnPushDefault_DisabledBorder = DisabledBorder
        .btnPushDefault_DisabledBk     = Transparent
        .btnPushDefault_Text           = White
        .btnPushDefault_Border         = Blue
        .btnPushDefault_Bk             = Blue
        .btnPushDefault_PressedText    = White
        .btnPushDefault_PressedBorder  = Blue
        .btnPushDefault_PressedBk      = Blue
        .btnPushDefault_HotText        = White
        .btnPushDefault_HotBorder      = LightBlue
        .btnPushDefault_HotBk          = LightBlue

        .btnIcon_Icon         = Gray1
        .btnIcon_Text         = Gray1
        .btnIcon_Bk           = Transparent
        .btnIcon_DisabledIcon = Disabled
        .btnIcon_DisabledText = Disabled
        .btnIcon_DisabledBk   = Transparent
        .btnIcon_PressedIcon  = Gray1
        .btnIcon_PressedText  = Gray1
        .btnIcon_PressedBk    = NeutralPressedBk
        .btnIcon_HotIcon      = Gray1
        .btnIcon_HotText      = Gray1
        .btnIcon_HotBk        = NeutralHotBk

        .btnIcon_CheckedDisabledIcon = Disabled
        .btnIcon_CheckedDisabledText = Disabled
        .btnIcon_CheckedPressedIcon  = White
        .btnIcon_CheckedPressedText  = White
        .btnIcon_CheckedHotIcon      = White
        .btnIcon_CheckedHotText      = White
        .btnIcon_CheckedIcon         = White
        .btnIcon_CheckedText         = White
        .btnIcon_CheckedDisabledBk   = Transparent
        .btnIcon_CheckedPressedBk    = AccentPressedBk
        .btnIcon_CheckedHotBk        = AccentHotBk
        .btnIcon_CheckedBk           = Transparent
        .btnIcon_CheckedMark         = Color.lighter(Color.fromArgb(Blue), 0.2)
        .btnIcon_CheckedPressedMark  = Blue
        .btnIcon_CheckedHotMark      = Color.lighter(Color.fromArgb(Blue), 0.1)
        .btnIcon_CheckedDisabledMark = Disabled

        .label_Text         = Gray1
        .label_TextLight    = Gray2
        .label_Text1        = 0xFFCC0000
        .label_Text2        = 0xFF008A00
        .label_Text3        = 0xFFCC0000
        .label_DisabledText = Disabled
        .label_Icon         = Gray2
        .label_DisabledIcon = Gray5

        .btnCheck_Text           = Gray1
        .btnCheck_Border         = Gray3
        .btnCheck_Mark           = Gray1
        .btnCheck_Bk             = Transparent
        .btnCheck_PressedText    = Gray1
        .btnCheck_PressedBorder  = Blue
        .btnCheck_PressedMark    = Blue
        .btnCheck_PressedBk      = AccentPressedBk
        .btnCheck_HotText        = Gray1
        .btnCheck_HotBorder      = Blue
        .btnCheck_HotMark        = Blue
        .btnCheck_HotBk          = AccentHotBk
        .btnCheck_DisabledText   = Disabled
        .btnCheck_DisabledBorder = Disabled
        .btnCheck_DisabledMark   = Disabled
        .btnCheck_DisabledBk     = Transparent
        .btnCheck_CheckedText    = Gray1
        .btnCheck_CheckedBk      = Transparent
        .btnCheck_CheckedBorder  = Blue
        .btnCheck_CheckedMark    = Blue

        .toolTip_Bk     = 0xFFFFFFE0
        .toolTip_Border = 0xFFAAAAAA
        .toolTip_Text   = Gray1

        .url_Text    = Blue
        .url_HotText = Color.lighter(Color.fromArgb(Blue), 0.2)

        .edit_Border         = Gray6
        .edit_FocusBorder    = Blue
        .edit_HotBorder      = LightBlue
        .edit_DisabledBorder = Gray7
        .edit_Bk             = White
        .edit_DisabledBk     = Gray8
        .edit_ErrorBk        = White
        .edit_HotBk          = White
        .edit_FocusBk        = White
        .edit_Note           = Gray5
        .edit_Text           = Gray1
        .edit_TextUnit       = Gray4
        .edit_DisabledText   = Gray5
        .edit_SelectedBk     = Color.lighter(Color.fromArgb(Blue), 0.5)
        .edit_ErrorBorder    = 0xFFFF0000

        .richEdit_Bk             = Gray8
        .richEdit_TextSpecial    = Gray3
        .richEdit_Text           = Gray1
        .richEdit_SelText        = White
        .richEdit_SelTextNoFocus = Gray1
        .richEdit_SelBk          = Color.darker(Color.fromArgb(Blue), 0.2)
        .richEdit_SelBkNoFocus   = Gray7
        .richEdit_Caret          = Gray1
        .richEdit_CurLineBorder  = Gray7

        .btnToggle_DisabledBorder   = Disabled
        .btnToggle_DisabledMark     = Disabled
        .btnToggle_DisabledBk       = Transparent
        .btnToggle_OffBorder        = Gray3
        .btnToggle_OffMark          = Gray3
        .btnToggle_OffBk            = Transparent
        .btnToggle_OffHotBorder     = Blue
        .btnToggle_OffHotMark       = Blue
        .btnToggle_OffHotBk         = AccentHotBk
        .btnToggle_OffPressedBorder = Blue
        .btnToggle_OffPressedMark   = Blue
        .btnToggle_OffPressedBk     = AccentPressedBk
        .btnToggle_OnBorder         = Blue
        .btnToggle_OnMark           = White
        .btnToggle_OnBk             = Blue
        .btnToggle_OnHotBorder      = LightBlue
        .btnToggle_OnHotMark        = White
        .btnToggle_OnHotBk          = LightBlue
        .btnToggle_OnPressedBorder  = Blue
        .btnToggle_OnPressedMark    = White
        .btnToggle_OnPressedBk      = Blue

        .slider_BkLeft            = Gray6
        .slider_BkMiddle          = Gray6
        .slider_BkRight           = Gray6
        .slider_HilightBk         = Blue
        .slider_Mark              = Blue
        .slider_HotMark           = LightBlue
        .slider_PressedMark       = Blue
        .slider_DisabledMark      = Gray5
        .slider_DisabledBk        = Gray7
        .slider_DisabledHilightBk = Gray6
        .slider_StepBk            = Color.darker(Color.fromArgb(Gray6), 0.08)
        .slider_HilightStepBk     = Color.darker(Color.fromArgb(Blue), 0.1)
        .slider_HotStepBk         = LightBlue

        .circular_Bk             = Transparent
        .circular_DisabledBk     = Transparent
        .circular_Circle         = Gray6
        .circular_DisabledCircle = Gray7
        .circular_Mark           = Blue
        .circular_HotMark        = LightBlue
        .circular_PressedMark    = Blue
        .circular_DisabledMark   = Gray5
        .circular_Step           = Gray5
        .circular_DisabledStep   = Gray6
        .circular_RangeArc       = Blue

        .tabItem_DisabledText             = Gray5
        .tabItem_SelectedText             = Gray1
        .tabItem_HotText                  = Gray1
        .tabItem_Text                     = Color.darker(Color.fromArgb(Gray1), 0.3)
        .tabItem_FlatSelected             = Blue
        .tabItem_FlatHot                  = AccentHotBk
        .tabItem_RoundSelected            = Gray7
        .tabItem_RoundHot                 = AccentHotBk
        .tabItem_ButtonSelected           = Gray7
        .tabItem_ButtonHot                = AccentHotBk
        .tabItem_PushButtonSelected       = Blue
        .tabItem_PushButtonSelectedText   = White
        .tabItem_PushButtonSelectedBorder = Blue
        .tabItem_PushButtonHot            = AccentHotBk
        .tabItem_PushButtonHotText        = Gray1
        .tabItem_PushButtonHotBorder      = Blue
        .tabItem_PushButtonText           = Gray1
        .tabItem_PushButtonBk             = Gray8
        .tabItem_PushButtonBorder         = Gray6
        .tabBar_FlatBk                    = Gray8
        .tabBar_RoundBk                   = Gray8
        .tabView_FlatBk                   = Gray7
        .tabView_RoundBk                  = Gray7

        .menuPopup_Bk         = White
        .menuPopup_Border     = Gray7
        .menuPopup_Shadow     = 0x33000000
        .menuPopup_Separator  = Gray7
        .menuBar_Bk           = Gray7
        .menuBar_Border       = 0
        .menuBar_SelectedBk   = AccentHotBk
        .menuBar_SelectedText = Gray1

        .popupItem_Text         = Gray1
        .popupItem_RightText    = Gray3
        .popupItem_DisabledText = Gray5
        .popupItem_HotText      = White
        .popupItem_HotRightText = White
        .popupItem_HotBk        = Blue

        .scrollBar_Bk         = Gray8
        .scrollBar_HotBk      = 0x10000000
        .scrollBar_DisabledBk = 0
        .scrollBar_Box        = Gray6
        .scrollBar_HotBox     = Gray5
        .scrollBar_PressedBox = Gray4

        .comboBox_Border           = Gray6
        .comboBox_HotBorder        = LightBlue
        .comboBox_DisabledBorder   = Gray7
        .comboBox_SelectedBorder   = Blue
        .comboBox_Bk               = White
        .comboBox_HotBk            = AccentHotBk
        .comboBox_DisabledBk       = Gray8
        .comboBox_SelectedBk       = White
        .comboBox_Text             = Gray1
        .comboBox_HotText          = Gray1
        .comboBox_DisabledText     = Gray5
        .comboBox_SelectedText     = Gray1
        .comboBoxItem_Text         = Gray1
        .comboBoxItem_HotBk        = Blue
        .comboBoxItem_HotText      = White
        .comboBoxItem_CheckMark    = Blue
        .comboBoxItem_HotCheckMark = White

        .popupList_Separator    = Gray7
        .popupList_HotBk        = Blue
        .popupList_Text         = Gray1
        .popupList_HotText      = White
        .popupList_CheckMark    = Blue
        .popupList_HotCheckMark = White

        .frameWnd_SmallShadow    = 0x25000000
        .frameWnd_Border         = Gray6
        .frameWnd_PopupBorder    = Gray5
        .frameWnd_FocusBorder    = Blue
        .frameWnd_DisabledBorder = Gray7
        .frameWnd_Bk             = Gray8
        .frameWnd_DisabledBk     = Gray8
        .frameWnd_FocusBk        = Gray8

        .listItem_FocusSelectedBk   = Blue
        .listItem_FocusSelectedText = White
        .listItem_SelectedBk        = AccentPressedBk
        .listItem_SelectedText      = Gray1
        .listItem_HotBk             = AccentHotBk
        .listItem_DisabledText      = Gray5
        .listItem_Text              = Gray1
        .listItem_Separator         = Color.lighter(Color.fromArgb(Gray1), 0.12)
        .listItem_AlternateBk       = 0x08000000
        .listItem_Line              = Gray7

        .headerItem_DisabledText = Gray5
        .headerItem_HotText      = Gray1
        .headerItem_HotBk        = AccentHotBk
        .headerItem_ClickedBk    = AccentPressedBk
        .headerItem_Text         = Gray1
        .headerItem_Separator    = Gray6
        .header_Bk               = Gray7

        .splitView_TitleBk = Gray6
        .splitView_Bar     = Gray7
        .splitView_BarHot  = Blue

        .progressBar_DisabledBorder = Gray7
        .progressBar_DisabledBk     = Transparent
        .progressBar_DisabledMark   = Gray6
        .progressBar_Border         = Gray6
        .progressBar_Bk             = Gray8
        .progressBar_Mark           = Blue

        .palPicker_Border    = Gray6
        .palPicker_HotBorder = Blue

        .colorPicker_Border    = 0x1A000000
        .colorPicker_BackAlpha = Gray7
        .colorPicker_Mark      = Gray3

        .imageRect_Fg = White

        .spinner_Dot = Gray1

        // Light theme: gentle, desaturated pastel backgrounds with soft (not fully saturated)
        // readable text, so the chips read as a light tint rather than a loud block. Status icons
        // keep their native colors and stand out against the muted fill.
        .embInfo_CriticalBk      = 0xFFF5DEDE
        .embInfo_CriticalText    = 0xFF9C4A4A
        .embInfo_InformationBk   = 0xFFDEE7F6
        .embInfo_InformationText = 0xFF2E4270
        .embInfo_MessageBk       = 0xFFF4EACB
        .embInfo_MessageText     = 0xFF7C6636

        .prop_FocusBk     = AccentPressedBk
        .prop_FocusBorder = Blue
        .prop_HotBk       = AccentHotBk
        .prop_HotBorder   = Transparent
        .prop_GridBorder  = Gray7
        .prop_GridColumn  = Gray7
        .prop_SectionBk   = Gray8
        .prop_CategBk     = Gray8
    }

    private mtd applySwagAccent(accent, activeText, neutralHot, neutralPressed: Color)
    {
        .hilight              = accent
        .hilightLight         = accent
        .hilightDark          = accent
        .hilightLightContrast = activeText
        .activeRail           = accent

        .btnPush_PressedBorder     = accent
        .btnPush_HotBorder         = accent
        .btnPushFlat_PressedBorder = accent
        .btnPushFlat_HotBorder     = accent

        .btnPushDefault_Text          = activeText
        .btnPushDefault_Border        = accent
        .btnPushDefault_Bk            = accent
        .btnPushDefault_PressedText   = activeText
        .btnPushDefault_PressedBorder = accent
        .btnPushDefault_PressedBk     = accent
        .btnPushDefault_HotText       = activeText
        .btnPushDefault_HotBorder     = accent
        .btnPushDefault_HotBk         = accent

        .btnIcon_CheckedPressedIcon = accent
        .btnIcon_CheckedPressedText = accent
        .btnIcon_CheckedHotIcon     = accent
        .btnIcon_CheckedHotText     = accent
        .btnIcon_CheckedIcon        = accent
        .btnIcon_CheckedText        = accent
        .btnIcon_CheckedPressedBk   = neutralPressed
        .btnIcon_CheckedHotBk       = neutralHot
        .btnIcon_CheckedBk          = .transparent
        .btnIcon_CheckedMark        = accent
        .btnIcon_CheckedPressedMark = accent
        .btnIcon_CheckedHotMark     = accent

        .btnCheck_PressedBorder = accent
        .btnCheck_PressedMark   = accent
        .btnCheck_HotBorder     = accent
        .btnCheck_HotMark       = accent
        .btnCheck_CheckedBorder = accent
        .btnCheck_CheckedMark   = accent

        .url_Text               = accent
        .url_HotText            = accent
        .edit_FocusBorder       = accent
        .edit_HotBorder         = accent
        .edit_SelectedBk        = neutralPressed
        .richEdit_SelBk         = neutralPressed
        .richEdit_CurLineBorder = neutralHot

        .btnToggle_OffHotBorder     = accent
        .btnToggle_OffHotMark       = accent
        .btnToggle_OffPressedBorder = accent
        .btnToggle_OffPressedMark   = accent
        .btnToggle_OnBorder         = accent
        .btnToggle_OnMark           = accent
        .btnToggle_OnBk             = neutralPressed
        .btnToggle_OnHotBorder      = accent
        .btnToggle_OnHotMark        = accent
        .btnToggle_OnHotBk          = neutralHot
        .btnToggle_OnPressedBorder  = accent
        .btnToggle_OnPressedMark    = accent
        .btnToggle_OnPressedBk      = neutralPressed

        .slider_HilightBk     = accent
        .slider_Mark          = accent
        .slider_HotMark       = accent
        .slider_PressedMark   = accent
        .slider_HilightStepBk = accent
        .slider_HotStepBk     = accent

        .circular_Mark        = accent
        .circular_HotMark     = accent
        .circular_PressedMark = accent
        .circular_RangeArc    = accent

        .tabItem_SelectedText             = .text
        .tabItem_FlatSelected             = neutralPressed
        .tabItem_FlatHot                  = neutralHot
        .tabItem_RoundSelected            = neutralPressed
        .tabItem_RoundHot                 = neutralHot
        .tabItem_ButtonSelected           = neutralPressed
        .tabItem_ButtonHot                = neutralHot
        .tabItem_PushButtonSelected       = neutralPressed
        .tabItem_PushButtonSelectedText   = .text
        .tabItem_PushButtonSelectedBorder = .border
        .tabItem_PushButtonHot            = neutralHot
        .tabItem_PushButtonHotBorder      = .border

        .menuBar_SelectedBk     = neutralHot
        .menuBar_SelectedText   = .text
        .popupItem_HotBk        = neutralHot
        .popupItem_HotText      = .text
        .popupItem_HotRightText = .text

        .comboBox_HotBorder        = accent
        .comboBox_SelectedBorder   = accent
        .comboBoxItem_HotBk        = neutralHot
        .comboBoxItem_HotText      = .text
        .comboBoxItem_CheckMark    = accent
        .comboBoxItem_HotCheckMark = accent
        .popupList_HotBk           = neutralHot
        .popupList_HotText         = .text
        .popupList_CheckMark       = accent
        .popupList_HotCheckMark    = accent

        .frameWnd_FocusBorder       = accent
        .listItem_FocusSelectedBk   = neutralPressed
        .listItem_FocusSelectedText = .text
        .listItem_SelectedBk        = neutralPressed
        .listItem_HotBk             = neutralHot
        .headerItem_HotBk           = neutralHot
        .headerItem_ClickedBk       = neutralPressed
        .splitView_BarHot           = accent
        .progressBar_Mark           = accent
        .palPicker_HotBorder        = accent
        .prop_FocusBk               = neutralPressed
        .prop_FocusBorder           = accent
        .prop_HotBk                 = neutralHot
    }

    // Applies the dark Swag application palette: Voltage over Ink with neutral structure.
    mtd setSwagDark()
    {
        const Ink         = 0xFF0B0B0D
        const View        = 0xFF15151A
        const Panel       = 0xFF202026
        const Raised      = 0xFF2A2A32
        // Hover has to be seen from across the surface without shouting. A step of nine
        // levels over the raised ground it usually sits on read as nothing at all.
        const NeutralHot  = 0xFF41414E
        const Pressed     = 0xFF52525F
        const Line        = 0xFF3D3D48
        const ControlLine = 0xFF6B6B77
        const Text        = 0xFFE9E9ED
        const SoftText    = 0xFFB4B4BE
        const FaintText   = 0xFF91919D
        const Voltage     = 0xFFF7F900

        .setDark()

        .bk     = Ink
        .border = Line
        .text   = Text

        .wnd_Bk                      = Panel
        .wnd_CaptionBk               = Raised
        .wnd_CaptionBkNotActived     = Panel
        .wnd_CaptionText             = Text
        .wnd_CaptionNotActivatedText = SoftText
        .wnd_Border                  = ControlLine
        .view_Bk                     = View
        .dlg_Bk                      = Panel
        .dlg_BtnBarBk                = View

        .btnPush_StrongText   = Ink
        .btnPush_StrongBorder = Voltage
        .btnPush_StrongBk     = Voltage
        .btnPush_Text         = Text
        .btnPush_Border       = ControlLine
        .btnPush_Bk           = Raised
        .btnPush_PressedText  = Text
        .btnPush_PressedBk    = Pressed
        .btnPush_HotText      = Text
        .btnPush_HotBk        = NeutralHot

        .btnPushFlat_Text      = Text
        .btnPushFlat_HotText   = Text
        .btnPushFlat_HotBk     = NeutralHot
        .btnPushFlat_PressedBk = Pressed
        .btnIcon_Icon          = Text
        .btnIcon_Text          = Text
        .btnIcon_HotIcon       = Text
        .btnIcon_HotText       = Text
        .btnIcon_HotBk         = NeutralHot
        .btnIcon_PressedBk     = Pressed

        .label_Text      = Text
        .label_TextLight = SoftText
        .label_Icon      = Text
        .disabled        = FaintText

        .edit_Border    = ControlLine
        .edit_HotBorder = ControlLine
        .edit_Bk        = Raised
        .edit_HotBk     = Raised
        .edit_FocusBk   = Raised
        .edit_Text      = Text
        .edit_Note      = FaintText
        .edit_TextUnit  = SoftText
        .richEdit_Bk    = View
        .richEdit_Text  = Text
        .richEdit_Caret = Text

        .menuPopup_Bk        = Panel
        .menuPopup_Border    = Line
        .menuPopup_Separator = Line
        .menuBar_Bk          = Ink
        .menuBar_Border      = Line
        .popupItem_Text      = Text
        .popupItem_RightText = SoftText
        .scrollBar_Bk        = View
        .scrollBar_Box       = FaintText

        .comboBox_Border       = ControlLine
        .comboBox_Bk           = Raised
        .comboBox_HotBk        = Raised
        .comboBox_SelectedBk   = Raised
        .comboBox_Text         = Text
        .comboBox_HotText      = Text
        .comboBox_SelectedText = Text
        .comboBoxItem_Text     = Text
        .popupList_Separator   = Line
        .popupList_Text        = Text

        .frameWnd_Border       = Line
        .frameWnd_PopupBorder  = ControlLine
        .frameWnd_Bk           = Panel
        .frameWnd_FocusBk      = Panel
        .listItem_Text         = Text
        .listItem_SelectedText = Text

        // A list separator row carries a group label, so it reads as a faint label,
        // not as a hairline.
        .listItem_Separator = FaintText
        .listItem_Line      = Line
        .headerItem_Text       = Text
        .headerItem_Separator  = Line
        .header_Bk             = Panel
        .splitView_TitleBk     = Panel
        .splitView_Bar         = Line
        .progressBar_Border    = ControlLine
        .progressBar_Bk        = View
        .prop_GridBorder       = Line
        .prop_GridColumn       = Line
        .prop_SectionBk        = View
        .prop_CategBk          = View

        .applySwagAccent(Color.fromArgb(Voltage), Color.fromArgb(Ink), Color.fromArgb(NeutralHot), Color.fromArgb(Pressed))
    }

    // Applies the light Swag application palette: Ink over Paper with neutral structure.
    mtd setSwagLight()
    {
        const Ink        = 0xFF0B0B0D
        const Paper      = 0xFFFFFFFF
        const Panel      = 0xFFF7F7F5
        const Raised     = 0xFFFFFFFF
        const Line       = 0xFFE2E2DF
        const Text       = 0xFF1B1B1D
        const SoftText   = 0xFF55555C
        const FaintText  = 0xFF83838D
        const NeutralHot = 0xFFF0F0ED
        const Pressed    = 0xFFE7E7E3

        .setLight()

        .bk     = Paper
        .border = Line
        .text   = Text

        .wnd_Bk                      = Paper
        .wnd_CaptionBk               = Paper
        .wnd_CaptionBkNotActived     = Panel
        .wnd_CaptionText             = Text
        .wnd_CaptionNotActivatedText = SoftText
        .wnd_Border                  = Line
        .view_Bk                     = Paper
        .dlg_Bk                      = Panel
        .dlg_BtnBarBk                = Paper

        .btnPush_StrongText   = Paper
        .btnPush_StrongBorder = Ink
        .btnPush_StrongBk     = Ink
        .btnPush_Text         = Text
        .btnPush_Border       = Line
        .btnPush_Bk           = Raised
        .btnPush_PressedText  = Text
        .btnPush_PressedBk    = Pressed
        .btnPush_HotText      = Text
        .btnPush_HotBk        = NeutralHot

        .label_Text      = Text
        .label_TextLight = SoftText
        .label_Icon      = Text
        .disabled        = FaintText

        .edit_Border    = Line
        .edit_Bk        = Raised
        .edit_HotBk     = Raised
        .edit_FocusBk   = Raised
        .edit_Text      = Text
        .edit_Note      = FaintText
        .edit_TextUnit  = SoftText
        .richEdit_Bk    = Paper
        .richEdit_Text  = Text
        .richEdit_Caret = Text

        .menuPopup_Bk        = Paper
        .menuPopup_Border    = Line
        .menuPopup_Separator = Line
        .menuBar_Bk          = Paper
        .menuBar_Border      = Line
        .popupItem_Text      = Text
        .popupItem_RightText = SoftText
        .scrollBar_Bk        = Panel
        .scrollBar_Box       = FaintText

        .comboBox_Border       = Line
        .comboBox_Bk           = Raised
        .comboBox_HotBk        = Raised
        .comboBox_SelectedBk   = Raised
        .comboBox_Text         = Text
        .comboBox_HotText      = Text
        .comboBox_SelectedText = Text
        .comboBoxItem_Text     = Text
        .popupList_Separator   = Line
        .popupList_Text        = Text

        .frameWnd_Border       = Line
        .frameWnd_PopupBorder  = Line
        .frameWnd_Bk           = Paper
        .frameWnd_FocusBk      = Paper
        .listItem_Text         = Text
        .listItem_SelectedText = Text

        // A list separator row carries a group label, so it reads as a faint label,
        // not as a hairline.
        .listItem_Separator = FaintText
        .listItem_Line      = Line
        .headerItem_Text       = Text
        .headerItem_Separator  = Line
        .header_Bk             = Panel
        .splitView_TitleBk     = Panel
        .splitView_Bar         = Line
        .progressBar_Border    = Line
        .progressBar_Bk        = Paper
        .prop_GridBorder       = Line
        .prop_GridColumn       = Line
        .prop_SectionBk        = Paper
        .prop_CategBk          = Paper

        .applySwagAccent(Color.fromArgb(Ink), Color.fromArgb(Paper), Color.fromArgb(NeutralHot), Color.fromArgb(Pressed))
    }
}
