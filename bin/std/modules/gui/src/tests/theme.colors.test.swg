#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// Encre is the dark theme of the charter, so the tokens it is written with are pinned rather than
// described: a change here is a change to every application, and it has to be written down.
#test
{
    let p = ThemeColors.encrePalette()
    Swag.assert(p.ground == 0xFF17181C)
    Swag.assert(p.surface == 0xFF1F2026)
    Swag.assert(p.raised == 0xFF2A2C33)
    Swag.assert(p.line == 0xFF33353D)
    Swag.assert(p.text == 0xFFECEDF0)
    Swag.assert(p.softText == 0xFFA3A6B0)
    Swag.assert(p.faintText == 0xFF737783)
    Swag.assert(p.signature.ground == Voltage and Voltage == 0xFFF7F900)
    Swag.assert(p.alternate.ground == Arc and Arc == 0xFF38BDF8)
    Swag.assert(p.link == 0xFF7DD3FC)
    Swag.assert(p.selection == 0x2938BDF8)
    Swag.assert(p.highlight == 0x38F7F900)
    Swag.assert(p.critical.mark == 0xFFFF6B6B and p.critical.ground == 0x1FFF6B6B)
    Swag.assert(p.caution.mark == 0xFFF2B544 and p.caution.ground == 0x1FF2B544)
    Swag.assert(p.info.mark == Arc)
    Swag.assert(p.live == 0xFF4ADE80)
}

// Papier is the light theme of the charter, pinned the same way.
#test
{
    let p = ThemeColors.papierPalette()
    Swag.assert(p.ground == 0xFFF5F4F0)
    Swag.assert(p.surface == 0xFFFFFFFF)
    Swag.assert(p.raised == 0xFFEBEAE5)
    Swag.assert(p.line == 0xFFE0DED7)
    Swag.assert(p.text == 0xFF1A1B1E)
    Swag.assert(p.softText == 0xFF55585F)
    Swag.assert(p.faintText == 0xFF72757C)
    Swag.assert(p.alternate.ground == 0xFF0A7FB5)
    Swag.assert(p.link == 0xFF0A6FA0)
    Swag.assert(p.selection == 0xFFDCEFFA)
    Swag.assert(p.highlight == 0xFFFBF68A)
    Swag.assert(p.critical.mark == 0xFFC42B2B and p.critical.ground == 0xFFFBE9E9)
    Swag.assert(p.caution.mark == 0xFFA36A00 and p.caution.ground == 0xFFFBF1DC)
    Swag.assert(p.live == 0xFF15803D)
}

// Voltage acts. On Encre the primary action is a Voltage block carrying ink, and the focus ring and
// the caret are Voltage; on Papier the same button is turned over, ink carrying paper, and the
// ring and the caret are ink. Voltage is never written on paper.
#test
{
    var encre, papier: ThemeColors
    encre.setDark()
    papier.setLight()

    Swag.assert(encre.btnPush_StrongBk == Voltage and encre.btnPush_StrongText == encre.ground)
    Swag.assert(encre.btnPushDefault_Bk == Voltage)
    Swag.assert(encre.focusRing == Voltage and encre.caret == Voltage and encre.edit_FocusBorder == Voltage)
    Swag.assert(encre.searchMatch_Bk.a < 255 and encre.searchMatch_Bk.withAlpha(255) == Voltage)
    Swag.assert(encre.searchMatch_Border == Voltage)

    Swag.assert(papier.btnPush_StrongBk == papier.text and papier.btnPush_StrongText == papier.ground)
    Swag.assert(papier.focusRing == papier.text and
                papier.caret == papier.text and
                papier.edit_FocusBorder == papier.text)
    Swag.assert(papier.searchMatch_Bk.withAlpha(255) == papier.highlight and papier.searchMatch_Border == papier.text)

    // No part of Papier is written in Voltage: a yellow mark on paper is a mark nobody sees.
    let type = assume cast(const *Swag.TypeInfoStruct, #typeof(ThemeColors))
    for field in type.fields
    {
        let color = cast(const *Color, (cast([*] u8, &papier) + field.offset))[]
        Swag.assert(color.argb != Voltage.argb)
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

        Swag.assert(colors.btnCheck_CheckedBk == palette.alternate.ground)
        Swag.assert(colors.btnRadio_CheckedMark == colors.arc)
        Swag.assert(colors.btnToggle_OnBk == palette.alternate.ground)
        Swag.assert(colors.slider_HilightBk == palette.alternate.ground)
        Swag.assert(colors.progressBar_Mark == palette.alternate.ground)
        Swag.assert(colors.tabItem_FlatSelected == colors.arc)
        Swag.assert(colors.btnIcon_CheckedIcon == colors.arc)
        Swag.assert(colors.popupItem_Marker == colors.arc)
        Swag.assert(colors.popupList_CheckMark == colors.arc)
        Swag.assert(colors.listItem_SelectedBk == palette.selection)
        Swag.assert(colors.popupItem_HotBk == palette.selection)
        Swag.assert(colors.url_Text == colors.link)

        for ground in [palette.ground, palette.surface, palette.raised]
        {
            Swag.assert(colors.arc.contrastRatio(ground) >= 3.5)
            Swag.assert(colors.focusRing.contrastRatio(ground) >= 3.5)
            Swag.assert(colors.critical.contrastRatio(ground) >= 3.5)
            Swag.assert(colors.live.contrastRatio(ground) >= 3.5)
        }

        // The charter names the live dot in both themes, so the derivation keeps it as written.
        Swag.assert(colors.live == palette.live)

        // A link is a word, read on the window or on a floating surface.
        for ground in [palette.ground, palette.surface] do
            Swag.assert(colors.link.contrastRatio(ground) >= 4.5)

        // The check is written in the ink Arc carries: ink on Encre, white on Papier.
        Swag.assert(colors.btnCheck_CheckedMark.contrastRatio(colors.btnCheck_CheckedBk) >= 3.5)
        Swag.assert(colors.btnPush_StrongText.contrastRatio(colors.btnPush_StrongBk) >= 4.5)

        // A notice is a tinted ground, a dot in its tone and body ink.
        Swag.assert(colors.embInfo_CriticalText == palette.text)
        Swag.assert(colors.embInfo_CriticalMark == colors.critical)
        Swag.assert(colors.embInfo_MessageMark == colors.caution)
        Swag.assert(colors.embInfo_InformationMark == colors.info)

        // A submenu chevron only reports continuation, so it stays below the wording.
        Swag.assert(colors.popupItem_SubmenuMarker == palette.faintText)
        Swag.assert(colors.popupItem_RightText == palette.faintText)
    }
}

// Every state of a control differs from the one before it, and disabled is weaker than rest.
#test
{
    for palette in [ThemeColors.encrePalette(), ThemeColors.papierPalette()]
    {
        var colors: ThemeColors
        colors.apply(palette)

        Swag.assert(colors.btnPushDefault_Bk != colors.btnPushDefault_HotBk)
        Swag.assert(colors.btnPushDefault_Bk != colors.btnPushDefault_PressedBk)
        Swag.assert(colors.btnPushDefault_HotBk != colors.btnPushDefault_PressedBk)
        Swag.assert(colors.btnPush_StrongBk != colors.btnPush_StrongHotBk)
        Swag.assert(colors.btnPush_StrongBk != colors.btnPush_StrongPressedBk)
        Swag.assert(colors.btnPush_Bk != colors.btnPush_HotBk)
        Swag.assert(colors.btnPush_HotBk != colors.btnPush_PressedBk)
        Swag.assert(colors.btnPush_Border != colors.btnPush_HotBorder)
        Swag.assert(colors.edit_Border != colors.edit_HotBorder)
        Swag.assert(colors.edit_HotBorder != colors.edit_FocusBorder)
        Swag.assert(colors.btnCheck_CheckedBk != colors.btnCheck_CheckedHotBk)
        Swag.assert(colors.btnToggle_OnBk != colors.btnToggle_OnHotBk)
        Swag.assert(colors.btnPush_DestructiveText == colors.critical)
        Swag.assert(colors.btnPush_DisabledBorder != colors.btnPush_Border)
        Swag.assert(colors.edit_DisabledBorder != colors.edit_Border)

        let rest     = colors.btnPush_Text.contrastRatio(palette.ground)
        let disabled = colors.btnPush_DisabledText.contrastRatio(palette.ground)
        Swag.assert(disabled < colors.label_TextFaint.contrastRatio(palette.ground))
        Swag.assert(disabled < rest)
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
        Swag.assert(colors.wnd_Bk == palette.ground)
        Swag.assert(colors.dlg_Bk == palette.surface)
        Swag.assert(colors.menuPopup_Bk == palette.surface)
        Swag.assert(colors.wnd_Border.a == 255)

        // The title and the window buttons are faint; a button reaches the body ink under the
        // pointer, and close the critical ink. The glyph is the soft ink at about 55 %.
        Swag.assert(colors.wnd_CaptionText == palette.faintText)
        Swag.assert(colors.wnd_BtnIcon == palette.faintText)
        Swag.assert(colors.wnd_BtnHotIcon == palette.text)
        Swag.assert(colors.wnd_BtnCloseHotIcon == colors.critical)
        Swag.assert(colors.wnd_CaptionMark.argb & 0x00FFFFFF == palette.softText.argb & 0x00FFFFFF)
        Swag.assert(colors.wnd_CaptionMark.a > 0x80 and colors.wnd_CaptionMark.a < 0x96)
    }

    // A colored mark keeps its tile on Papier, where a keyed-out Voltage glyph would vanish.
    var encre, papier: ThemeColors
    encre.setDark()
    papier.setLight()
    Swag.assert(markReadsOn(encre.ground))
    Swag.assert(not markReadsOn(papier.ground))
}

// The measures of the charter, and the tiles drawn with them: every tile publishes the corner its
// family has, so a mark drawn over a control follows the same corner the control was drawn with.
#test
{
    var theme: Theme
    let metrics = &theme.metrics
    let rects   = &theme.rects

    Swag.assert(metrics.surfaceWnd_CornerRadius == 10)
    Swag.assert(metrics.corner_Floating == 12)
    Swag.assert(metrics.corner_Menu == 10)
    Swag.assert(metrics.corner_Control == 6)
    Swag.assert(metrics.corner_Chip == 4)
    Swag.assert(metrics.btnPush_Height == 32)
    Swag.assert(metrics.editBox_Height == 32)
    Swag.assert(metrics.comboBox_Height == 32)
    Swag.assert(metrics.list_LineHeight == 30)
    Swag.assert(metrics.menuPopup_ItemHeight == 30)
    Swag.assert(metrics.btnToggle_Width == 34 and metrics.btnToggle_Height == 20)
    Swag.assert(metrics.slider_BoxSize == 14)
    Swag.assert(metrics.progressBar_TrackSize == 4)
    Swag.assert(metrics.focusRing_Size == 2 and metrics.focusRing_Offset == 2)
    Swag.assert(metrics.scrollBar_Size - 2 * metrics.scrollBar_BoxPadding == 4)

    for rect in [rects.btnPush_Normal, rects.btnPush_NormalBorder, rects.edit_SquareBk, rects.edit_SquareBorder,
                 rects.edit_SquareStrongBorder, rects.btnIcon_SquareBk, rects.btnIcon_RoundSquareBk, rects.tabBar_RoundBk,
                 rects.frameWnd_SquareBk]
    {
        Swag.assert(rect.radius == metrics.corner_Control)
    }

    for rect in [rects.frameWnd_RoundBk, rects.frameWnd_RoundBorder, rects.panel_Bk] do
        Swag.assert(rect.radius == metrics.corner_Floating)
    Swag.assert(rects.menuPopup_Bk.radius == metrics.corner_Menu)
    Swag.assert(rects.btnCheck_Normal.radius == metrics.corner_Chip)

    // Changing theme changes colors only: both themes share the geometry of the charter.
    theme.setLight()
    Swag.assert(metrics.surfaceWnd_CornerRadius == 10 and rects.btnPush_Normal.radius == metrics.corner_Control)
    theme.setDark()
    Swag.assert(metrics.surfaceWnd_CornerRadius == 10 and rects.btnPush_Normal.radius == metrics.corner_Control)
}
