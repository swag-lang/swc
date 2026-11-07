#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// Encre is the dark theme of the charter, so the tokens it is written with are pinned rather than
// described: a change here is a change to every application, and it has to be written down.
#test
{
    let p = ThemeColors.encrePalette()
    Swag.require(p.ground == 0xFF17181C)
    Swag.require(p.surface == 0xFF1F2026)
    Swag.require(p.raised == 0xFF2A2C33)
    Swag.require(p.line == 0xFF33353D)
    Swag.require(p.text == 0xFFECEDF0)
    Swag.require(p.softText == 0xFFA3A6B0)
    Swag.require(p.faintText == 0xFF737783)
    Swag.require(p.signature.ground == Voltage and Voltage == 0xFFF7F900)
    Swag.require(p.alternate.ground == Arc and Arc == 0xFF38BDF8)
    Swag.require(p.link == 0xFF7DD3FC)
    Swag.require(p.selection == 0x2938BDF8)
    Swag.require(p.highlight == 0x38F7F900)
    Swag.require(p.critical.mark == 0xFFFF6B6B and p.critical.ground == 0x1FFF6B6B)
    Swag.require(p.caution.mark == 0xFFF2B544 and p.caution.ground == 0x1FF2B544)
    Swag.require(p.info.mark == Arc)
    Swag.require(p.live == 0xFF4ADE80)
}

// Papier is the light theme of the charter, pinned the same way.
#test
{
    let p = ThemeColors.papierPalette()
    Swag.require(p.ground == 0xFFF5F4F0)
    Swag.require(p.surface == 0xFFFFFFFF)
    Swag.require(p.raised == 0xFFEBEAE5)
    Swag.require(p.line == 0xFFE0DED7)
    Swag.require(p.text == 0xFF1A1B1E)
    Swag.require(p.softText == 0xFF55585F)
    Swag.require(p.faintText == 0xFF72757C)
    Swag.require(p.alternate.ground == 0xFF0A7FB5)
    Swag.require(p.link == 0xFF0A6FA0)
    Swag.require(p.selection == 0xFFDCEFFA)
    Swag.require(p.highlight == 0xFFFBF68A)
    Swag.require(p.critical.mark == 0xFFC42B2B and p.critical.ground == 0xFFFBE9E9)
    Swag.require(p.caution.mark == 0xFFA36A00 and p.caution.ground == 0xFFFBF1DC)
    Swag.require(p.live == 0xFF15803D)
}

// Voltage acts. On Encre the primary action is a Voltage block carrying ink, and the focus ring and
// the caret are Voltage; on Papier the same button is turned over, ink carrying paper, and the
// ring and the caret are ink. Voltage is never written on paper.
#test
{
    var encre, papier: ThemeColors
    encre.setDark()
    papier.setLight()

    Swag.require(encre.btnPush_StrongBk == Voltage and encre.btnPush_StrongText == encre.ground)
    Swag.require(encre.btnPushDefault_Bk == Voltage)
    Swag.require(encre.focusRing == Voltage and encre.caret == Voltage and encre.edit_FocusBorder == Voltage)
    Swag.require(encre.searchMatch_Bk.a < 255 and encre.searchMatch_Bk.withAlpha(255) == Voltage)
    Swag.require(encre.searchMatch_Border == Voltage)

    Swag.require(papier.btnPush_StrongBk == papier.text and papier.btnPush_StrongText == papier.ground)
    Swag.require(papier.focusRing == papier.text and
                 papier.caret == papier.text and
                 papier.edit_FocusBorder == papier.text)
    Swag.require(papier.searchMatch_Bk.withAlpha(255) == papier.highlight and papier.searchMatch_Border == papier.text)

    // No part of Papier is written in Voltage: a yellow mark on paper is a mark nobody sees.
    let type = assume cast(const *Swag.TypeInfoStruct, #typeof(ThemeColors))
    for field in type.fields
    {
        let color = cast(const *Color, (cast([*] u8, &papier) + field.offset))[]
        Swag.require(color.argb != Voltage.argb)
    }
}

// Arc chooses: a checked box, a radio, a switch that is on, a slider and a progress fill, the
// underline of the active tab, a checked tool, a menu check, and the selection ground of rows,
// menus and segments. Every one of them reads on every opaque ground of its theme.
#test
{
    for palette in [ThemeColors.encrePalette(), ThemeColors.papierPalette()]
    {
        var colors: ThemeColors
        colors.apply(palette)

        Swag.require(colors.btnCheck_CheckedBk == palette.alternate.ground)
        Swag.require(colors.btnRadio_CheckedMark == colors.arc)
        Swag.require(colors.btnToggle_OnBk == palette.alternate.ground)
        Swag.require(colors.slider_HilightBk == palette.alternate.ground)
        Swag.require(colors.progressBar_Mark == palette.alternate.ground)
        Swag.require(colors.tabItem_FlatSelected == colors.arc)
        Swag.require(colors.btnIcon_CheckedIcon == colors.arc)
        Swag.require(colors.popupItem_Marker == colors.arc)
        Swag.require(colors.popupList_CheckMark == colors.arc)
        Swag.require(colors.listItem_SelectedBk == palette.selection)
        Swag.require(colors.popupItem_HotBk == palette.selection)
        Swag.require(colors.url_Text == colors.link)

        for ground in [palette.ground, palette.surface, palette.raised]
        {
            Swag.require(colors.arc.contrastRatio(ground) >= 3.5)
            Swag.require(colors.focusRing.contrastRatio(ground) >= 3.5)
            Swag.require(colors.critical.contrastRatio(ground) >= 3.5)
            Swag.require(colors.live.contrastRatio(ground) >= 3.5)
        }

        // The charter names the live dot in both themes, so the derivation keeps it as written.
        Swag.require(colors.live == palette.live)

        // A link is a word, read on the window or on a floating surface.
        for ground in [palette.ground, palette.surface] do
            Swag.require(colors.link.contrastRatio(ground) >= 4.5)

        // The check is written in the ink Arc carries: ink on Encre, white on Papier.
        Swag.require(colors.btnCheck_CheckedMark.contrastRatio(colors.btnCheck_CheckedBk) >= 3.5)
        Swag.require(colors.btnPush_StrongText.contrastRatio(colors.btnPush_StrongBk) >= 4.5)

        // A notice is a tinted ground, a dot in its tone and body ink.
        Swag.require(colors.embInfo_CriticalText == palette.text)
        Swag.require(colors.embInfo_CriticalMark == colors.critical)
        Swag.require(colors.embInfo_MessageMark == colors.caution)
        Swag.require(colors.embInfo_InformationMark == colors.info)

        // A submenu chevron only reports continuation, so it stays below the wording.
        Swag.require(colors.popupItem_SubmenuMarker == palette.faintText)
        Swag.require(colors.popupItem_RightText == palette.faintText)
    }
}

// Every state of a control differs from the one before it, and disabled is weaker than rest.
#test
{
    for palette in [ThemeColors.encrePalette(), ThemeColors.papierPalette()]
    {
        var colors: ThemeColors
        colors.apply(palette)

        Swag.require(colors.btnPushDefault_Bk != colors.btnPushDefault_HotBk)
        Swag.require(colors.btnPushDefault_Bk != colors.btnPushDefault_PressedBk)
        Swag.require(colors.btnPushDefault_HotBk != colors.btnPushDefault_PressedBk)
        Swag.require(colors.btnPush_StrongBk != colors.btnPush_StrongHotBk)
        Swag.require(colors.btnPush_StrongBk != colors.btnPush_StrongPressedBk)
        Swag.require(colors.btnPush_Bk != colors.btnPush_HotBk)
        Swag.require(colors.btnPush_HotBk != colors.btnPush_PressedBk)
        Swag.require(colors.btnPush_Border != colors.btnPush_HotBorder)
        Swag.require(colors.edit_Border != colors.edit_HotBorder)
        Swag.require(colors.edit_HotBorder != colors.edit_FocusBorder)
        Swag.require(colors.btnCheck_CheckedBk != colors.btnCheck_CheckedHotBk)
        Swag.require(colors.btnToggle_OnBk != colors.btnToggle_OnHotBk)
        Swag.require(colors.btnPush_DestructiveText == colors.critical)
        Swag.require(colors.btnPush_DisabledBorder != colors.btnPush_Border)
        Swag.require(colors.edit_DisabledBorder != colors.edit_Border)

        let rest     = colors.btnPush_Text.contrastRatio(palette.ground)
        let disabled = colors.btnPush_DisabledText.contrastRatio(palette.ground)
        Swag.require(disabled >= 3)
        Swag.require(disabled < rest)
    }
}

// The charter draws no caption band, no glow and no rail: the top strip is the window ground, its
// chrome is faint, and the outline of a surface is an opaque hairline.
#test
{
    for palette in [ThemeColors.encrePalette(), ThemeColors.papierPalette()]
    {
        var colors: ThemeColors
        colors.apply(palette)
        Swag.require(colors.wnd_Bk == palette.ground)
        Swag.require(colors.dlg_Bk == palette.surface)
        Swag.require(colors.menuPopup_Bk == palette.raised)
        Swag.require(colors.wnd_Border.a == 255)

        // The title and the window buttons are faint; a button reaches the body ink under the
        // pointer, and close the critical ink. The application mark keeps a contrasting electric ink.
        Swag.require(colors.wnd_CaptionText == palette.faintText)
        Swag.require(colors.wnd_BtnIcon == palette.faintText)
        Swag.require(colors.wnd_BtnHotIcon == palette.text)
        Swag.require(colors.wnd_BtnCloseHotIcon == colors.critical)
        Swag.require(colors.wnd_CaptionMark == (markReadsOn(palette.ground) ? colors.signature : colors.arc))
        Swag.require(colors.wnd_CaptionMark.contrastRatio(palette.ground) >= 3)
    }

    // A colored mark keeps its tile on Papier, where a keyed-out Voltage glyph would vanish.
    var encre, papier: ThemeColors
    encre.setDark()
    papier.setLight()
    Swag.require(encre.edit_Border.contrastRatio(encre.surface) >= 1.5)
    Swag.require(encre.menuPopup_Border == encre.edit_Border)
    Swag.require(markReadsOn(encre.ground))
    Swag.require(not markReadsOn(papier.ground))
}

// The measures of the charter, and the tiles drawn with them: every tile publishes the corner its
// family has, so a mark drawn over a control follows the same corner the control was drawn with.
#test
{
    var theme: Theme
    let metrics = &theme.metrics
    let rects   = &theme.rects

    Swag.require(metrics.surfaceWnd_CornerRadius == 10)
    Swag.require(metrics.corner_Floating == 12)
    Swag.require(metrics.corner_Menu == 10)
    Swag.require(metrics.corner_Control == 6)
    Swag.require(metrics.corner_Chip == 4)
    Swag.require(metrics.btnPush_Height == 32)
    Swag.require(metrics.editBox_Height == 32)
    Swag.require(metrics.comboBox_Height == 32)
    Swag.require(metrics.list_LineHeight == 30)
    Swag.require(metrics.menuPopup_ItemHeight == 30)
    Swag.require(metrics.btnToggle_Width == 34 and metrics.btnToggle_Height == 20)
    Swag.require(metrics.slider_BoxSize == 14)
    Swag.require(metrics.progressBar_TrackSize == 4)
    Swag.require(metrics.focusRing_Size == 2 and metrics.focusRing_Offset == 2)
    Swag.require(metrics.scrollBar_Size - 2 * metrics.scrollBar_BoxPadding == 4)

    for rect in [rects.btnPush_Normal, rects.btnPush_NormalBorder, rects.edit_SquareBk, rects.edit_SquareBorder,
                 rects.edit_SquareStrongBorder, rects.btnIcon_SquareBk, rects.btnIcon_RoundSquareBk, rects.tabBar_RoundBk,
                 rects.frameWnd_SquareBk]
    {
        Swag.require(rect.radius == metrics.corner_Control)
    }

    for rect in [rects.frameWnd_RoundBk, rects.frameWnd_RoundBorder, rects.panel_Bk] do
        Swag.require(rect.radius == metrics.corner_Floating)
    Swag.require(rects.menuPopup_Bk.radius == metrics.corner_Menu)
    Swag.require(rects.btnCheck_Normal.radius == metrics.corner_Chip)

    // Changing theme changes colors only: both themes share the geometry of the charter.
    theme.setLight()
    Swag.require(metrics.surfaceWnd_CornerRadius == 10 and rects.btnPush_Normal.radius == metrics.corner_Control)
    theme.setDark()
    Swag.require(metrics.surfaceWnd_CornerRadius == 10 and rects.btnPush_Normal.radius == metrics.corner_Control)
}
