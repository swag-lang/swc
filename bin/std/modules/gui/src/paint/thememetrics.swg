#global public

using Core

// Defines logical dimensions, spacing, and animation timing for themed GUI elements.
struct ThemeMetrics
{
    defaultFontSize:          u32 = 14     // Theme measurement used for default font size.
    defaultFixedFontSize:     u32 = 16     // Theme measurement used for default fixed font size.
    // Transparent margin the drop shadow is cast into. It has to hold the spread plus the offset,
    // or the shadow is cut off by the edge of the window instead of fading out into it.
    surfaceWnd_ShadowSize:    f32 = 18
    surfaceWnd_CornerRadius:  f32 = 18     // Corner of a surface. The Swag palettes soften it to 8; see setSwagGeometry.
    surfaceWnd_ShadowSpread:  f32 = 14     // How far the drop shadow reaches out from the body.
    surfaceWnd_ShadowOffsetX: f32 = 0      // Sideways displacement of the drop shadow.
    surfaceWnd_ShadowOffsetY: f32 = 4      // Downward displacement of the drop shadow, which is what lifts the window.

    wnd_BorderSize:            f32 = 1        // Theme measurement used for wnd border size.
    wnd_BigCaptionCY:          f32 = 42       // Theme measurement used for wnd big caption cy.
    wnd_SmallCaptionCY:        f32 = 32       // Theme measurement used for wnd small caption cy.
    wnd_CaptionMarginTitle:    f32 = 14       // Theme measurement used for wnd caption margin title.
    wnd_CaptionIconSize:       f32 = 20       // Side of the mark a drawn caption shows beside its title.
    wnd_CaptionButtonMargin:   f32 = 5        // Theme measurement used for wnd caption button margin.
    wnd_CaptionButtonGlyph:    f32 = 16       // Side of a caption glyph. Chrome, so it sits at the row size of the chart.
    wnd_CaptionButtonAspect:   f32 = 1.35     // Theme measurement used for wnd caption button aspect.
    wnd_CaptionButtonMinWidth: f32 = 44       // Theme measurement used for wnd caption button min width.
    wnd_SizingBorderSize:      f32 = 8        // Theme measurement used for wnd sizing border size.
    wnd_TopSizingBorderSize:   f32 = 7        // Theme measurement used for wnd top sizing border size.

    tabBar_FlatHeight:   f32 = 40     // Theme measurement used for tab bar flat height.
    tabBar_RoundHeight:  f32 = 28     // Theme measurement used for tab bar round height.
    tabBar_ButtonHeight: f32 = 32     // Theme measurement used for tab bar button height.

    btnPush_Padding:    f32 = 5       // Theme measurement used for btn push padding.
    btnPush_TextMargin: f32 = 14      // Room a measured caption keeps on each side of a push button.
    btnPush_Width:      f32 = 100     // Theme measurement used for btn push width.
    btnPush_Height:     f32 = 30      // Theme measurement used for btn push height.

    iconText_Margin: f32 = 8     // Air between a glyph and the word it leads. Air is the first separator, so it is generous.

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
    slider_BoxSize:   f32 = 12      // Side of the thumb; an indicator, not a control to grab with a finger.
    slider_StepSize:  f32 = 6       // Theme measurement used for slider step size.

    circular_Size:       f32 = 40     // Theme measurement used for circular size.
    circular_MarkerSize: f32 = 5      // Theme measurement used for circular marker size.

    menuPopup_Padding:         f32 = 12     // Theme measurement used for menu popup padding.
    menuPopup_SpaceLines:      f32 = 6      // Theme measurement used for menu popup space lines.
    menuPopup_ShadowSize:      f32 = 10     // Theme measurement used for menu popup shadow size.
    menuPopup_IconMargin:      f32 = 6      // Air between the active rule and the glyph of an entry.
    menuPopup_IconTextMargin:  f32 = 10     // Air between the glyph or check mark of an entry and its wording.
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

    spinner_Size:     f32 = 24      // Side of a spinner created without a size.
    spinner_DotCount: f32 = 8       // Number of dots forming the ring.
    spinner_Speed:    f32 = 1.1     // Turns of the ring per second.

    colorPicker_RoundPick:  f32 = 6     // Theme measurement used for color picker round pick.
    colorPicker_SquarePick: f32 = 6     // Theme measurement used for color picker square pick.

    label_Height: f32 = 24     // Theme measurement used for label height.

    separator_HairlineSize: f32 = 1     // Theme measurement used for separator hairline size.
    separator_AccentSize:   f32 = 4     // Theme measurement used for separator accent size.

    // The rule that marks the active item — a checked tool, the open menu, the hovered
    // entry. It is thin, and it keeps its distance from whatever it marks.
    //
    // On a cell it is a mark and stops short of both ends by `activeRail_Margin`; on a row
    // of a list or a menu it runs the whole edge, because a rule shorter than the row it
    // marks reads as a second, smaller object inside it.
    activeRail_Size:   f32 = 3     // Thickness of the rule.
    activeRail_Margin: f32 = 8     // Air a cell mark keeps at each end, and between the rule and the content.

    // The ring that says where the keyboard is. It is a rule around a control, not a fill on
    // it, and it keeps clear of the control's own border so the two never read as one thick edge.
    focusRing_Size:  f32 = 1     // Thickness of the ring.
    focusRing_Inset: f32 = 2     // Air the ring keeps inside the control's rectangle.
    focusRing_Cut:   f32 = 4     // Width of the 45 degree cut opening each of its corners.

    richEdit_Padding: f32 = 5     // Theme measurement used for rich edit padding.
    toolTip_Padding:  f32 = 2     // Theme measurement used for tool tip padding.
}
