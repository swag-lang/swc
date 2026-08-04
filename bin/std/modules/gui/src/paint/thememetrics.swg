#global public

using Core

// Defines logical dimensions, spacing, and animation timing for themed GUI elements.
struct ThemeMetrics
{
    defaultFontSize:          u32 = 14     // Theme measurement used for default font size.
    defaultFixedFontSize:     u32 = 16     // Theme measurement used for default fixed font size.
    surfaceWnd_ShadowSize:    f32 = 0      // Theme measurement used for surface wnd shadow size.
    surfaceWnd_CornerRadius:  f32 = 18     // Theme measurement used for surface wnd corner radius.
    surfaceWnd_ShadowSpread:  f32 = 16     // Theme measurement used for surface wnd shadow spread.
    surfaceWnd_ShadowOffsetX: f32 = 0      // Theme measurement used for surface wnd shadow offset x.
    surfaceWnd_ShadowOffsetY: f32 = 3      // Theme measurement used for surface wnd shadow offset y.
    surfaceWnd_ShadowLayers:  u32 = 8      // Theme measurement used for surface wnd shadow layers.

    wnd_BorderSize:            f32 = 1        // Theme measurement used for wnd border size.
    wnd_BigCaptionCY:          f32 = 42       // Theme measurement used for wnd big caption cy.
    wnd_SmallCaptionCY:        f32 = 32       // Theme measurement used for wnd small caption cy.
    wnd_CaptionMarginTitle:    f32 = 14       // Theme measurement used for wnd caption margin title.
    wnd_CaptionButtonMargin:   f32 = 5        // Theme measurement used for wnd caption button margin.
    wnd_CaptionButtonAspect:   f32 = 1.35     // Theme measurement used for wnd caption button aspect.
    wnd_CaptionButtonMinWidth: f32 = 44       // Theme measurement used for wnd caption button min width.
    wnd_SizingBorderSize:      f32 = 8        // Theme measurement used for wnd sizing border size.
    wnd_TopSizingBorderSize:   f32 = 7        // Theme measurement used for wnd top sizing border size.

    tabBar_FlatHeight:   f32 = 40     // Theme measurement used for tab bar flat height.
    tabBar_RoundHeight:  f32 = 28     // Theme measurement used for tab bar round height.
    tabBar_ButtonHeight: f32 = 32     // Theme measurement used for tab bar button height.

    btnPush_Padding: f32 = 5       // Theme measurement used for btn push padding.
    btnPush_Width:   f32 = 100     // Theme measurement used for btn push width.
    btnPush_Height:  f32 = 30      // Theme measurement used for btn push height.

    iconText_Margin: f32 = 4     // Theme measurement used for icon text margin.

    btnCheck_Size:    f32 = 24     // Theme measurement used for btn check size.
    btnCheck_Padding: f32 = 4      // Theme measurement used for btn check padding.

    dialog_Padding:    f32 = 20     // Theme measurement used for dialog padding.
    dialog_BtnPadding: f32 = 5      // Theme measurement used for dialog btn padding.

    editBox_SquarePadding: Math.Vector4 = {10, 5, 10, 5}     // Theme measurement used for edit box square padding.
    editBox_RoundPadding:  Math.Vector4 = {12, 5, 12, 5}     // Theme measurement used for edit box round padding.
    editBox_FlatPadding:   Math.Vector4 = {12, 0, 12, 5}     // Theme measurement used for edit box flat padding.
    editBox_Width:         f32          = 100                // Theme measurement used for edit box width.
    editBox_Height:        f32          = 32                 // Theme measurement used for edit box height.
    editBox_UnitMargin:    f32          = 3                  // Theme measurement used for edit box unit margin.

    btnToggle_Width:  f32 = 50     // Theme measurement used for btn toggle width.
    btnToggle_Height: f32 = 26     // Theme measurement used for btn toggle height.

    slider_Width:     f32 = 200     // Theme measurement used for slider width.
    slider_Height:    f32 = 26      // Theme measurement used for slider height.
    slider_TrackSize: f32 = 18      // Theme measurement used for slider track size.
    slider_BoxSize:   f32 = 18      // Theme measurement used for slider box size.
    slider_StepSize:  f32 = 6       // Theme measurement used for slider step size.

    circular_Size:       f32 = 40     // Theme measurement used for circular size.
    circular_MarkerSize: f32 = 5      // Theme measurement used for circular marker size.

    menuPopup_Padding:         f32 = 12     // Theme measurement used for menu popup padding.
    menuPopup_SpaceLines:      f32 = 6      // Theme measurement used for menu popup space lines.
    menuPopup_ShadowSize:      f32 = 10     // Theme measurement used for menu popup shadow size.
    menuPopup_IconMargin:      f32 = 2      // Theme measurement used for menu popup icon margin.
    menuPopup_IconTextMargin:  f32 = 6      // Theme measurement used for menu popup icon text margin.
    menuPopup_SeparatorHeight: f32 = 8      // Theme measurement used for menu popup separator height.
    menuPopup_BarItemOverlap:  f32 = 12     // Theme measurement used for menu popup bar item overlap.

    menuBar_Height:       f32 = 30     // Theme measurement used for menu bar height.
    menuBar_SpaceBetween: f32 = 24     // Theme measurement used for menu bar space between.

    iconBar_ButtonsPadding: f32 = 4     // Theme measurement used for icon bar buttons padding.

    scrollBar_NormalSize: f32 = 20     // Theme measurement used for scroll bar normal size.
    scrollBar_SmallSize:  f32 = 10     // Theme measurement used for scroll bar small size.
    scrollBar_BoxPadding: f32 = 4      // Theme measurement used for scroll bar box padding.
    scrollBar_BoxMinSize: f32 = 20     // Theme measurement used for scroll bar box min size.

    comboBox_Width:          f32 = 150     // Theme measurement used for combo box width.
    comboBox_Height:         f32 = 32      // Theme measurement used for combo box height.
    comboBox_RightMargin:    f32 = 30      // Theme measurement used for combo box right margin.
    comboBox_Padding:        f32 = 10      // Theme measurement used for combo box padding.
    comboBox_IconTextMargin: f32 = 6       // Theme measurement used for combo box icon text margin.

    popupList_Padding:          f32 = 6     // Theme measurement used for popup list padding.
    popupList_IconTextMargin:   f32 = 6     // Theme measurement used for popup list icon text margin.
    popupList_SeparatorPadding: f32 = 4     // Theme measurement used for popup list separator padding.

    btnIcon_WidthArrow:    f32 = 10     // Theme measurement used for btn icon width arrow.
    btnIcon_HeightArrow:   f32 = 6      // Theme measurement used for btn icon height arrow.
    btnIcon_Padding:       f32 = 4      // Theme measurement used for btn icon padding.
    btnIcon_MarginArrow:   f32 = 4      // Theme measurement used for btn icon margin arrow.
    btnIcon_SpacingIcon:   f32 = 4      // Theme measurement used for btn icon spacing icon.
    btnIcon_SpacingArrowH: f32 = 8      // Theme measurement used for btn icon spacing arrow h.
    btnIcon_SpacingArrowV: f32 = 4      // Theme measurement used for btn icon spacing arrow v.
    btnIcon_SpacingTextH:  f32 = 8      // Theme measurement used for btn icon spacing text h.
    btnIcon_SpacingTextV:  f32 = 0      // Theme measurement used for btn icon spacing text v.

    frameWnd_SquarePadding:            f32          = 5                  // Theme measurement used for frame wnd square padding.
    frameWnd_RoundPadding:             f32          = 5                  // Theme measurement used for frame wnd round padding.
    frameWnd_FlatPadding:              f32          = 2                  // Theme measurement used for frame wnd flat padding.
    frameWnd_SmallShadowSize:          Math.Vector4 = {5, 5, 15, 15}     // Theme measurement used for frame wnd small shadow size.
    frameWnd_AnchorWidth:              f32          = 24                 // Theme measurement used for frame wnd anchor width.
    frameWnd_AnchorHeight:             f32          = 10                 // Theme measurement used for frame wnd anchor height.
    frameWnd_AnchorOverlap:            f32          = 2                  // Theme measurement used for frame wnd anchor overlap.
    frameWnd_AnchorRoundBorderMargin:  f32          = 16                 // Theme measurement used for frame wnd anchor round border margin.
    frameWnd_AnchorSquareBorderMargin: f32          = 8                  // Theme measurement used for frame wnd anchor square border margin.

    list_Padding:    f32 = 5      // Theme measurement used for list padding.
    list_ExpandSize: f32 = 22     // Theme measurement used for list expand size.

    header_Height:    f32          = 35                 // Theme measurement used for header height.
    header_Padding:   Math.Vector4 = {10, 5, 10, 5}     // Theme measurement used for header padding.
    header_Separator: f32          = 5                  // Theme measurement used for header separator.

    splitView_BarSize: f32 = 8     // Theme measurement used for split view bar size.

    progressBar_Height:     f32 = 18      // Theme measurement used for progress bar height.
    progressBar_ClipOffset: f32 = 2       // Theme measurement used for progress bar clip offset.
    progressBar_SpeedInf:   f32 = 0.5     // Theme measurement used for progress bar speed inf.

    colorPicker_RoundPick:  f32 = 6     // Theme measurement used for color picker round pick.
    colorPicker_SquarePick: f32 = 6     // Theme measurement used for color picker square pick.

    label_Height: f32 = 24     // Theme measurement used for label height.

    separator_HairlineSize: f32 = 1     // Theme measurement used for separator hairline size.
    separator_AccentSize:   f32 = 4     // Theme measurement used for separator accent size.

    richEdit_Padding: f32 = 5     // Theme measurement used for rich edit padding.
    toolTip_Padding:  f32 = 2     // Theme measurement used for tool tip padding.
}
