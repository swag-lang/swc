#global public

using Pixel

// Defines the semantic color palette consumed by GUI controls and painters.
//
// One value per painted part. Nothing here is written by hand: every field is derived from
// a [[Gui.ThemePalette]] by [[Gui.ThemeColors.apply]], so a theme answers for every control
// or for none, and the same relationship holds in every theme. A theme that wants one part
// different overrides it afterwards through a theme sheet.
//
// The first group is the vocabulary of the charter itself — ground, surface, raised, line, the
// three inks, Voltage acting and Arc choosing, the highlight and the status tones — for anything
// that paints a part no control owns. The groups after it are one per control.
struct ThemeColors
{
    public
    {
        // The three slots rich text addresses with `<p1>`, `<p2>` and `<p3>`.
        richColor1: Color     // First rich-text palette slot.
        richColor2: Color     // Second rich-text palette slot.
        richColor3: Color     // Third rich-text palette slot.

        // Tint a surface fades to while a modal box holds it. It multiplies the whole surface,
        // so it is a dimming factor rather than a color.
        surfaceDisabled: Color

        ground:     Color     // The window and the document read in it.
        surface:    Color     // A floating surface: a lens, a sheet, an inspector, a dialog, a menu, a popover.
        raised:     Color     // The ground under the pointer, and the track of a slider or a progress.
        pressed:    Color     // The ground under the press, one step past `raised`.
        line:       Color     // Hairline edge of a field, a card, a separator.
        strongLine: Color     // The stronger rule of a hovered field, an unchecked box, a scroll bar thumb.

        text:      Color     // Body text.
        softText:  Color     // Secondary text and labels.
        faintText: Color     // Captions, units, hints.
        disabled:  Color     // Ink and rules of anything the reader cannot act on.

        // Voltage acts: the primary action, the focus ring, the caret. On Papier this is ink, the
        // same button turned over, because Voltage is never written on paper.
        signature:   Color     // Fill of the primary action, and the mark of what acts.
        onSignature: Color     // Ink legible on a fill of the signature.
        focusRing:   Color     // Ring drawn around the control the keyboard focus is on.
        caret:       Color     // The text caret.

        // Arc chooses: what is selected, on, elsewhere or in progress.
        arc:       Color     // The Arc mark: a checked box, a switch that is on, a fill, an underline, a chosen glyph.
        onArc:     Color     // Ink drawn on an Arc fill: the check mark of a checked box.
        link:      Color     // Link text.
        selection: Color     // Ground of a selected row, thumbnail, segment, or of a menu entry under the pointer.
        highlight: Color     // Ground of search occurrences and matched characters.

        // The current search occurrence. Encre marks it in Voltage; Papier keeps the highlight
        // ground and marks it with ink. The band is translucent, because a viewer draws it over
        // text it must not hide.
        searchMatch_Bk:     Color     // Translucent band over the current search occurrence.
        searchMatch_Border: Color     // Crisp mark of the current search occurrence.
        searchMatch_Glow:   Color     // Outer animated glow around the current search occurrence.

        critical:   Color     // Text, dots and rings reporting an operation that stopped.
        criticalBk: Color     // Tinted ground of a critical notice.
        caution:    Color     // Dots and marks of something that needs attention.
        cautionBk:  Color     // Tinted ground of a caution notice.
        info:       Color     // Dots and marks of something worth knowing.
        infoBk:     Color     // Tinted ground of an information notice.

        transparent: Color     // Nothing drawn. Always zero; named so a sheet can point a part at it.

        // The three strengths of the theme's translucent veil, drawn over whatever is behind
        // them. White over a dark ground, black over a light one.
        veilSoft:   Color     // Lightest translucent veil.
        veilMedium: Color     // Middle-strength translucent veil.
        veilStrong: Color     // Strongest translucent veil.

        // The window is the document: its top strip is the ground the content sits on, and the
        // chrome drawn there is quiet enough to read past. No band, no rail, no glow.
        wnd_Bk: Color     // Ground of a window body, its top strip included.
        wnd_CaptionText: Color     // Title of a window, centred in its top strip.
        wnd_CaptionMark: Color     // Monochrome application glyph at the leading corner of a window.

        // Outline of a whole surface. It must be opaque: the same stroke runs past every ground of
        // the window, and a translucent value would visibly change tone where those grounds meet.
        wnd_Border: Color

        // The window buttons are faint glyphs that reach full contrast under the pointer. Only the
        // press lays a ground under them; close turns critical, since it is the one that destroys.
        wnd_BtnIcon:           Color     // Glyph of a window button at rest.
        wnd_BtnHotIcon:        Color     // Glyph of a window button under the pointer or the press.
        wnd_BtnPressedBk:      Color     // Ground of a window button under the press.
        wnd_BtnCloseHotIcon:   Color     // Glyph of the close button under the pointer or the press.
        wnd_BtnClosePressedBk: Color     // Ground of the close button under the press.

        // Ink of the drop shadow. Its alpha is the darkening the shadow reaches where it meets the
        // body, not the alpha of any one ring: the shadow fades from nothing at the outer edge of the
        // margin up to this value against the window.
        wnd_Shadow: Color

        // The floating components of the charter — the lens, the information sheet, the
        // inspector, the mini-bar and the dock — stand on the surface ground with a hairline ring.
        floating_Shadow: Color     // Shadow a floating component casts.
        lens_Dim:        Color     // Dim laid over the window while the lens floats above it, so the work reads faintly behind it.

        view_Bk:           Color     // Ground content is read on.
        informationBar_Bk: Color     // Ground of a band reporting identity, context, or status.
        commandBar_Bk:     Color     // Ground of application-wide commands.
        toolBar_Bk:        Color     // Ground of tools specific to the current content.

        dlg_Bk: Color     // Ground of a dialog.

        // The primary action: Voltage with ink on Encre, ink with paper on Papier.
        btnPush_StrongText:   Color     // Label of a primary action.
        btnPush_StrongBorder: Color     // Border of a primary action.
        btnPush_StrongBk:     Color     // Fill of a primary action.

        // A primary action answers the pointer in its own color. Falling back to the hover of a
        // secondary button, it lost what made it the action of the surface exactly when the reader
        // was about to press it.
        btnPush_StrongHotText:       Color     // Label of a hovered primary action.
        btnPush_StrongHotBorder:     Color     // Border of a hovered primary action.
        btnPush_StrongHotBk:         Color     // Fill of a hovered primary action.
        btnPush_StrongPressedText:   Color     // Label of a pressed primary action.
        btnPush_StrongPressedBorder: Color     // Border of a pressed primary action.
        btnPush_StrongPressedBk:     Color     // Fill of a pressed primary action.

        // A button that is on: a mode the reader chose. Arc chooses, so it wears the selection
        // ground, writes in Arc and keeps a faint Arc ring — the same mark as a checked tool.
        btnPush_AlternateText:          Color     // Label of a button that is on.
        btnPush_AlternateBorder:        Color     // Border of a button that is on.
        btnPush_AlternateBk:            Color     // Fill of a button that is on.
        btnPush_AlternateHotText:       Color     // Label of a hovered button that is on.
        btnPush_AlternateHotBorder:     Color     // Border of a hovered button that is on.
        btnPush_AlternateHotBk:         Color     // Fill of a hovered button that is on.
        btnPush_AlternatePressedText:   Color     // Label of a pressed button that is on.
        btnPush_AlternatePressedBorder: Color     // Border of a pressed button that is on.
        btnPush_AlternatePressedBk:     Color     // Fill of a pressed button that is on.

        // The secondary button: transparent, a hairline ring, the body ink.
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

        // The destructive button: a secondary button whose label says what is lost.
        btnPush_DestructiveText:    Color     // Label of a destructive button.
        btnPush_DestructiveHotText: Color     // Label of a hovered or pressed destructive button.

        // The quiet button: its words alone, in the soft ink.
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

        // A checked tool: the selection ground, an Arc glyph and a faint Arc ring.
        btnIcon_CheckedDisabledIcon:        Color     // Glyph of a checked, disabled icon button.
        btnIcon_CheckedDisabledText:        Color     // Label of a checked, disabled icon button.
        btnIcon_CheckedPressedIcon:         Color     // Glyph of a checked, pressed icon button.
        btnIcon_CheckedPressedText:         Color     // Label of a checked, pressed icon button.
        btnIcon_CheckedHotIcon:             Color     // Glyph of a checked, hovered icon button.
        btnIcon_CheckedHotText:             Color     // Label of a checked, hovered icon button.
        btnIcon_CheckedIcon:                Color     // Glyph of a checked icon button.
        btnIcon_CheckedText:                Color     // Label of a checked icon button.
        btnIcon_CheckedDisabledBk:          Color     // Fill of a checked, disabled icon button.
        btnIcon_CheckedPressedBk:           Color     // Fill of a checked, pressed icon button.
        btnIcon_CheckedHotBk:               Color     // Fill of a checked, hovered icon button.
        btnIcon_CheckedBk:                  Color     // Fill of a checked icon button.
        btnIcon_CheckedMark:                Color     // Mark saying an icon button is checked: its ground, or the rule on one edge.
        btnIcon_CheckedPressedMark:         Color     // Checked mark under the press.
        btnIcon_CheckedHotMark:             Color     // Checked mark under the pointer.
        btnIcon_CheckedDisabledMark:        Color     // Checked mark of a disabled button.
        btnIcon_CheckedRing:                Color     // Faint ring around a checked icon button.
        btnIcon_CheckedRule:                Color     // Rule of a checked icon button marked on one edge.
        btnIcon_CheckedFrameBk:             Color     // Fill of a framed checked icon button.
        btnIcon_CheckedFrameHotBk:          Color     // Fill of a hovered framed checked icon button.
        btnIcon_CheckedFramePressedBk:      Color     // Fill of a pressed framed checked icon button.
        btnIcon_CheckedFrameDisabledBk:     Color     // Fill of a disabled framed checked icon button.
        btnIcon_CheckedFrameBorder:         Color     // Outline of a framed checked icon button.
        btnIcon_CheckedFrameHotBorder:      Color     // Outline of a hovered framed checked icon button.
        btnIcon_CheckedFramePressedBorder:  Color     // Outline of a pressed framed checked icon button.
        btnIcon_CheckedFrameDisabledBorder: Color     // Outline of a disabled framed checked icon button.

        label_Text:         Color     // Primary label text.
        label_TextLight:    Color     // Secondary label text.
        label_TextFaint:    Color     // Counts, status readouts, and other text a reader only glances at.
        label_DisabledText: Color     // Text of a disabled label.
        label_Icon:         Color     // Glyph beside a label.
        label_DisabledIcon: Color     // Glyph beside a disabled label.

        // A check box and a radio button. Off is a ring; on is Arc. The state a box is in survives
        // the pointer: hovering changes the ring, never the answer.
        btnCheck_Text:             Color     // Label of a check box.
        btnCheck_Border:           Color     // Ring of an unchecked box.
        btnCheck_Mark:             Color     // Mark inside an unchecked box; nothing is drawn there.
        btnCheck_Bk:               Color     // Fill of an unchecked box.
        btnCheck_PressedText:      Color     // Label of a pressed check box.
        btnCheck_PressedBorder:    Color     // Ring of a pressed, unchecked box.
        btnCheck_PressedMark:      Color     // Mark of a pressed box.
        btnCheck_PressedBk:        Color     // Fill of a pressed, unchecked box.
        btnCheck_HotText:          Color     // Label of a hovered check box.
        btnCheck_HotBorder:        Color     // Ring of a hovered, unchecked box.
        btnCheck_HotMark:          Color     // Mark of a hovered box.
        btnCheck_HotBk:            Color     // Fill of a hovered, unchecked box.
        btnCheck_DisabledText:     Color     // Label of a disabled check box.
        btnCheck_DisabledBorder:   Color     // Ring of a disabled box.
        btnCheck_DisabledMark:     Color     // Mark of a disabled box.
        btnCheck_DisabledBk:       Color     // Fill of a disabled box.
        btnCheck_CheckedText:      Color     // Label of a checked box.
        btnCheck_CheckedBk:        Color     // Fill of a checked box.
        btnCheck_CheckedBorder:    Color     // Border of a checked box.
        btnCheck_CheckedMark:      Color     // Check or dash drawn on a checked box.
        btnCheck_CheckedHotBk:     Color     // Fill and border of a checked box under the pointer.
        btnCheck_CheckedDisabledBk: Color    // Fill and border of a checked, disabled box.

        btnRadio_CheckedBorder:  Color     // Ring of a chosen radio button.
        btnRadio_CheckedMark:    Color     // Dot of a chosen radio button.
        btnRadio_CheckedHotMark: Color     // Ring and dot of a chosen radio button under the pointer.

        // A tool tip is a transient note rather than a part of the interface: the surface on
        // Encre, ink with paper text on Papier, where a white note on white paper would vanish.
        toolTip_Bk:     Color     // Ground of a tool tip.
        toolTip_Border: Color     // Border of a tool tip.
        toolTip_Text:   Color     // Text of a tool tip.

        // The marked-up text a tip may carry, answered against the tip's own ground.
        toolTip_Link:    Color     // A link inside a tool tip, at rest.
        toolTip_HotLink: Color     // A link inside a tool tip, under the pointer.
        toolTip_Rich1:   Color     // First rich-text palette slot inside a tool tip.
        toolTip_Rich2:   Color     // Second rich-text palette slot inside a tool tip.
        toolTip_Rich3:   Color     // Third rich-text palette slot inside a tool tip.

        url_Text:    Color     // A link at rest.
        url_HotText: Color     // A link under the pointer.

        edit_Border:         Color     // Ring of a field.
        edit_FocusBorder:    Color     // Ring of the focused field: two pixels of what acts.
        edit_HotBorder:      Color     // Ring of a hovered field.
        edit_DisabledBorder: Color     // Ring of a disabled field.
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
        edit_ErrorBorder:    Color     // Ring of a field holding a rejected value.
        edit_Caret:          Color     // Caret of a field.

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
        slider_HilightBk:         Color     // The filled part of the track.
        slider_Mark:              Color     // The knob.
        slider_MarkBorder:        Color     // The hairline ring of the knob.
        slider_HotMark:           Color     // The knob under the pointer.
        slider_PressedMark:       Color     // The knob under the press.
        slider_DisabledMark:      Color     // The knob of a disabled slider.
        slider_DisabledBk:        Color     // Track of a disabled slider.
        slider_DisabledHilightBk: Color     // Filled part of the track of a disabled slider.
        slider_StepBk:            Color     // A step marker on the empty part of the track.
        slider_HilightStepBk:     Color     // A step marker on the filled part of the track.
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
        tabItem_FlatSelected:             Color     // Underline of the selected flat tab.
        tabItem_FlatHot:                  Color     // Underline of a hovered flat tab.
        tabItem_RoundSelected:            Color     // Ground of the chosen segment of a round bar.
        tabItem_RoundLift:                Color     // Soft shadow lifting the chosen segment off its frame, transparent where it is not lifted.
        tabItem_RoundHot:                 Color     // Ground of a hovered segment of a round bar.
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
        tabBar_FlatLine:                  Color     // Hairline under a flat tab bar.
        tabBar_RoundBk:                   Color     // Raised frame of a round tab bar, which holds segments.
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

        popupItem_Text:                  Color     // An entry of a menu.
        popupItem_RightText:             Color     // The shortcut written after an entry.
        popupItem_DisabledText:          Color     // An entry the reader cannot choose.
        popupItem_HotText:               Color     // An entry under the pointer.
        popupItem_HotRightText:          Color     // The shortcut of an entry under the pointer.
        popupItem_HotBk:                 Color     // Ground of an entry under the pointer.
        popupItem_Marker:                Color     // Check or radio selection shown beside an entry.
        popupItem_HotMarker:             Color     // Check or radio selection under the pointer.
        popupItem_DisabledMarker:        Color     // Check or radio selection of an unavailable entry.
        popupItem_SubmenuMarker:         Color     // Chevron leading to a child menu.
        popupItem_HotSubmenuMarker:      Color     // Chevron leading to a child menu under the pointer.
        popupItem_DisabledSubmenuMarker: Color     // Chevron leading to an unavailable child menu.
        popupItem_Heading:               Color     // Title of a group of entries.

        optionSheet_HotBk:      Color     // Ground of the row of an option sheet under the pointer or the keyboard.
        optionSheet_Marker:     Color     // Check of the value in force on an option sheet.
        optionSheet_StepBorder: Color     // Outline of the buttons that step a value on an option sheet.

        scrollBar_Bk:         Color     // Track of a scroll bar.
        scrollBar_HotBk:      Color     // Track of a scroll bar under the pointer.
        scrollBar_DisabledBk: Color     // Track of a scroll bar with nothing to scroll.
        scrollBar_Box:        Color     // The thumb.
        scrollBar_HotBox:     Color     // The thumb under the pointer.
        scrollBar_PressedBox: Color     // The thumb under the press.

        comboBox_Border:         Color     // Ring of a combo box.
        comboBox_HotBorder:      Color     // Ring of a hovered combo box.
        comboBox_DisabledBorder: Color     // Ring of a disabled combo box.
        comboBox_SelectedBorder: Color     // Ring of a combo box whose list is open.
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
        listItem_Expand:            Color     // Chevron of a tree row.

        headerItem_DisabledText: Color     // Label of a disabled column head.
        headerItem_HotText:      Color     // Label of a column head under the pointer.
        headerItem_HotBk:        Color     // Ground of a column head under the pointer.
        headerItem_ClickedBk:    Color     // Ground of a column head under the press.
        headerItem_Text:         Color     // Label of a column head.
        headerItem_Separator:    Color     // Rule between two column heads, and under the header.
        header_Bk:               Color     // Ground of a header band.

        splitView_TitleBk: Color     // Ground of the title of a split pane.
        splitView_Bar:     Color     // The bar between two panes.
        splitView_BarHot:  Color     // The bar under the pointer.

        progressBar_DisabledBorder: Color     // Border of a disabled progress bar.
        progressBar_DisabledBk:     Color     // Track of a disabled progress bar.
        progressBar_DisabledMark:   Color     // Filled part of a disabled progress bar.
        progressBar_Border:         Color     // Border of a progress bar.
        progressBar_Bk:             Color     // Track of a progress bar.
        progressBar_Mark:           Color     // Filled part of a progress bar.

        palPicker_Border:      Color     // Outline of a swatch.
        palPicker_HotBorder:   Color     // Outline of a swatch under the pointer.
        palPicker_CheckedRing: Color     // Ring around the chosen swatch.

        colorPicker_Border:    Color     // Outline of the picker surfaces.
        colorPicker_BackAlpha: Color     // Ground shown through a translucent color.
        colorPicker_Mark:      Color     // The marker on a picker surface.

        // Tint a drawn image is multiplied by. White leaves the image alone, which is what an
        // image wants: it carries its own colors and owes the theme nothing.
        imageRect_Fg: Color

        spinner_Track: Color     // The ring a circular progress turns on.
        spinner_Mark:  Color     // The arc that turns.

        // A notice is a tinted ground of its tone, a dot in the tone, and body ink.
        embInfo_CriticalBk:      Color     // Ground of a notice reporting a failure.
        embInfo_CriticalText:    Color     // Text of a notice reporting a failure.
        embInfo_CriticalMark:    Color     // Dot of a notice reporting a failure.
        embInfo_InformationBk:   Color     // Ground of a notice offering guidance.
        embInfo_InformationText: Color     // Text of a notice offering guidance.
        embInfo_InformationMark: Color     // Dot of a notice offering guidance.
        embInfo_MessageBk:       Color     // Ground of a notice asking for attention.
        embInfo_MessageText:     Color     // Text of a notice asking for attention.
        embInfo_MessageMark:     Color     // Dot of a notice asking for attention.

        prop_FocusBk:     Color     // Ground of the focused row of a property grid.
        prop_FocusBorder: Color     // Legacy outline color for a property-related selection.
        prop_HotBk:       Color     // Ground of the row under the pointer.
        prop_HotBorder:   Color     // Legacy outline color for a property-related hot state.
        prop_GridBorder:  Color     // Outline of a property grid.
        prop_GridColumn:  Color     // Rule between the name column and the value column.
        prop_SectionBk:   Color     // Ground of a section head.
        prop_CategBk:     Color     // Ground of a category head.
    }
}

impl ThemeColors
{
    // How far a filled action travels under the pointer, and under the press. Enough to
    // be seen, never enough to read as a second color.
    private const StrongHotShift     = 0.12'f32
    private const StrongPressedShift = 0.26'f32

    // How far the ground under the press sits past the ground under the pointer.
    private const PressedShift = 0.08'f32

    // The three strengths of a veil, as alphas over the palette's veil ink.
    private const VeilSoftAlpha        = 0x14'u8
    private const VeilMediumAlpha      = 0x24'u8
    private const VeilStrongAlpha      = 0x34'u8
    private const SearchMatchBandAlpha = 0x66'u8
    private const SearchMatchGlowAlpha = 0x70'u8

    // Ground of alternating rows. Weaker than a soft veil: it must be found, never noticed.
    private const AlternateAlpha = 0x0A'u8

    // How faint the Arc ring of a chosen tool or a button that is on stays: found, not noticed.
    private const ChosenRingAlpha = 0x73'u8

    // Strength of the soft shadow under a chosen segment that is lifted off its frame: enough to
    // separate a white chip from a pale frame, never enough to read as a floating surface.
    private const SegmentLiftAlpha = 0x1A'u8

    // Strength of the application glyph in the corner of a window: about 55 %, so it signs the
    // window in either theme and is never read before the work.
    private const CaptionMarkAlpha = 0x8C'u8

    // Strength of the ground laid over the work while the lens is open: the document behind
    // reads at about a sixth of its strength, present but out of the way.
    private const LensDimAlpha = 0xD6'u8

    // How much of the shadow a floating surface casts on a dark ground. Darkness laid on near-black
    // reads as a hole rather than as air, so there the surface parts from the work mostly by its
    // lighter fill and its hairline, and the shadow only softens the edge.
    private const FloatingShadowDarkShare = 0.5'f32

    // How much of the shadow a floating surface casts on a light ground. The palette's shadow is
    // tuned for small, close shadows; spread as wide as a floating one, it would still be at
    // nearly full strength where the body ends and read as a grey edge under it. At this share
    // it darkens the paper by about a tenth there, and the body seems to rest on air.
    private const FloatingShadowLightShare = 0.6'f32

    // How far the stronger rule travels from the hairline toward the faint ink, and how far
    // disabled ink travels from the ground toward the body ink. The charter states the disabled
    // state as an opacity of 40 to 45 percent; written as a mix it stays opaque, so a disabled
    // label drawn twice never reads darker than one drawn once.
    private const StrongLineMix = 0.4'f32
    private const DisabledMix   = 0.42'f32

    // The ring of an unavailable control is the hairline at the opacity of disabled ink, so it
    // stays weaker than the ring of the same control at rest.
    private const DisabledLineMix = 0.45'f32

    // A knob is white in both themes: the one part of a switch or a slider that has to read as a
    // physical thing on any track. It is the only fixed ink of the controls.
    private const Knob: Color = 0xFFFFFFFF

    // How far a surface is dimmed while a modal box holds it. A dark surface takes a
    // heavier hand than a light one: the same multiplier that clearly recedes a white page
    // barely registers on near-black.
    private const DimDark  = 0xFFBBBBBB
    private const DimLight = 0xFFEEEEEE

    // How much contrast a mark owes the ground it lands on.
    //
    // Below three a rule, a ring or a glyph is not separated from what it is drawn over; the
    // extra half step is what a mark that is also a word — a link, a checked label — needs to
    // stay a word. A link asks for the full text bar of its own, against the ground it is read on.
    private const MarkContrast = 3.5'f32
    private const LinkContrast = 4.5'f32

    // Moves a fill by `amount` in whichever direction is visible on it.
    //
    // A light fill darkens and a dark one lightens. Always lightening looks obvious until
    // the fill is Voltage, which is already at the top of red and green: mixing it with
    // white can only raise blue, and the button reports nothing the eye can catch.
    private func shiftState(base: Color, amount: f32)->Color => base.relativeLuminance() > 0.5 ? Color.darker(base, amount) : Color.lighter(base, amount)

    // How many times a mark is allowed to be moved before the grounds are declared irreconcilable.
    // Each pass answers the ground the mark is nearest, which can hand it to another one; three
    // grounds need no more than one pass each, and the spare passes cost nothing once it reads.
    private const MarkPasses = 7

    // Returns the ground of `p` that `mark` has the hardest time on.
    //
    // It is the one nearest it, which is not the same as the extreme one: a mid-tone accent on a
    // dark theme clears the window ground easily and can disappear on the raised ground of a
    // control drawn over it.
    private func hardestGround(p: ThemePalette, mark: Color)->Color
    {
        var result = p.ground
        for candidate in [p.surface, p.raised] where mark.contrastRatio(candidate) < mark.contrastRatio(result) do
            result = candidate
        return result
    }

    // Returns `tone` with a mark that reads on every ground `p` paints.
    //
    // Deepening rather than replacing is the whole point: the hue survives, and a sheet that
    // writes a tone once still gets a legible hairline on both kinds of ground. Moving a mark can
    // hand it to a different ground, so the answer is looked for again until the worst one is
    // satisfied.
    private func readableTone(tone: ThemeTone, p: ThemePalette)->ThemeTone
    {
        var result = tone

        for MarkPasses
        {
            let ground = hardestGround(p, result.mark)
            if result.mark.contrastRatio(ground) >= MarkContrast do
                break
            result.mark.ensureContrast(ground, MarkContrast)
        }

        return result
    }

    // Derives every semantic color of the theme from `p`.
    //
    // This is the whole rule book, and it is the reason a theme cannot be half written: the
    // palette answers twenty-odd questions and every control is placed by the same
    // relationships, in the same order as the struct above. Read it as the specification of
    // what each part of the interface is allowed to be.
    mtd apply(p: ThemePalette)
    {
        // Every tone is made readable on the grounds of the theme before anything is derived from
        // it, so no part downstream has to know which mode it is being painted in.
        let signature = readableTone(p.signature, p)
        let alternate = readableTone(p.alternate, p)
        let critical  = readableTone(p.critical, p)
        let caution   = readableTone(p.caution, p)
        let info      = readableTone(p.info, p)

        // A filled action travels in its own color, whatever that color is. The mark and the
        // block travel separately, because a tone is allowed to point with one color and
        // fill with another — see [[Gui.ThemeTone]].
        let groundHot     = shiftState(signature.ground, StrongHotShift)
        let groundPressed = shiftState(signature.ground, StrongPressedShift)
        let arcHot        = shiftState(alternate.ground, StrongHotShift)
        let chosenRing    = alternate.mark.withAlpha(ChosenRingAlpha)

        let pressed    = shiftState(p.raised, PressedShift)
        let strongLine = Color.lerpRgb(p.line, p.faintText, StrongLineMix)
        let disabled   = Color.lerpRgb(p.ground, p.text, DisabledMix)
        let faintLine  = Color.lerpRgb(p.ground, p.line, DisabledLineMix)

        // A chosen segment is lifted when it is an opaque chip lighter than the raised frame it
        // stands in, as Papier's white one is; a wash, as on Encre, lies flat in its frame.
        let segmentLifted = p.segment.a == 0xFF and p.segment.relativeLuminance() > p.raised.relativeLuminance()

        .richColor1 = p.rich1
        .richColor2 = p.rich2
        .richColor3 = p.rich3

        .surfaceDisabled = p.ground.relativeLuminance() > 0.5 ? Color.fromArgb(DimLight) : Color.fromArgb(DimDark)

        .ground     = p.ground
        .surface    = p.surface
        .raised     = p.raised
        .pressed    = pressed
        .line       = p.line
        .strongLine = strongLine
        .text       = p.text
        .softText   = p.softText
        .faintText  = p.faintText
        .disabled   = disabled

        .signature   = signature.ground
        .onSignature = signature.onGround
        .focusRing   = signature.mark
        .caret       = signature.mark

        .arc       = alternate.mark
        .onArc     = alternate.onGround
        .link      = p.link
        .selection = p.selection
        .highlight = p.highlight
        .link.ensureContrast(p.ground, LinkContrast)

        .searchMatch_Bk     = p.currentMatch.ground.withAlpha(SearchMatchBandAlpha)
        .searchMatch_Border = p.currentMatch.mark
        .searchMatch_Glow   = p.currentMatch.ground.withAlpha(SearchMatchGlowAlpha)

        .critical    = critical.mark
        .criticalBk  = critical.ground
        .caution     = caution.mark
        .cautionBk   = caution.ground
        .info        = info.mark
        .infoBk      = info.ground
        .transparent = 0

        .veilSoft   = p.veil.withAlpha(VeilSoftAlpha)
        .veilMedium = p.veil.withAlpha(VeilMediumAlpha)
        .veilStrong = p.veil.withAlpha(VeilStrongAlpha)

        // The window is the document: no caption band, no glow. The glyph is the soft ink at a
        // little over half strength, so it signs the corner without becoming a block of brand.
        .wnd_Bk                = p.ground
        .wnd_CaptionText       = p.faintText
        .wnd_CaptionMark       = p.softText.withAlpha(CaptionMarkAlpha)
        .wnd_Border            = p.line
        .wnd_BtnIcon           = p.faintText
        .wnd_BtnHotIcon        = p.text
        .wnd_BtnPressedBk      = p.raised
        .wnd_BtnCloseHotIcon   = critical.mark
        .wnd_BtnClosePressedBk = critical.ground
        .wnd_Shadow            = p.shadow

        .floating_Shadow = p.shadow
        .lens_Dim        = p.ground.withAlpha(LensDimAlpha)
        let floatingShare = p.ground.relativeLuminance() <= 0.5 ? FloatingShadowDarkShare : FloatingShadowLightShare
        .floating_Shadow.a = cast(u8, cast(f32, p.shadow.a) * floatingShare)

        // Nothing on screen but the work: the bands an application used to frame its content
        // with are the ground the content sits on.
        .view_Bk           = p.ground
        .informationBar_Bk = p.ground
        .commandBar_Bk     = p.ground
        .toolBar_Bk        = p.ground

        .dlg_Bk = p.surface

        // The primary action is the signature block. The outline is the same block: on Papier the
        // signature is ink, and on Encre a Voltage edge on a Voltage fill is simply its own edge.
        .btnPush_StrongText          = signature.onGround
        .btnPush_StrongBorder        = signature.ground
        .btnPush_StrongBk            = signature.ground
        .btnPush_StrongHotText       = signature.onGround
        .btnPush_StrongHotBorder     = groundHot
        .btnPush_StrongHotBk         = groundHot
        .btnPush_StrongPressedText   = signature.onGround
        .btnPush_StrongPressedBorder = groundPressed
        .btnPush_StrongPressedBk     = groundPressed

        .btnPush_AlternateText          = alternate.mark
        .btnPush_AlternateBorder        = chosenRing
        .btnPush_AlternateBk            = p.selection
        .btnPush_AlternateHotText       = alternate.mark
        .btnPush_AlternateHotBorder     = alternate.mark
        .btnPush_AlternateHotBk         = p.selection
        .btnPush_AlternatePressedText   = alternate.mark
        .btnPush_AlternatePressedBorder = alternate.mark
        .btnPush_AlternatePressedBk     = pressed

        // The secondary button is transparent on its ground with a hairline ring, and earns a
        // raised fill under the pointer.
        .btnPush_Text           = p.text
        .btnPush_Border         = p.line
        .btnPush_Bk             = .transparent
        .btnPush_PressedText    = p.text
        .btnPush_PressedBorder  = strongLine
        .btnPush_PressedBk      = pressed
        .btnPush_HotText        = p.text
        .btnPush_HotBorder      = strongLine
        .btnPush_HotBk          = p.raised
        .btnPush_DisabledText   = disabled
        .btnPush_DisabledBorder = faintLine
        .btnPush_DisabledBk     = .transparent

        .btnPush_DestructiveText    = critical.mark
        .btnPush_DestructiveHotText = critical.mark

        // The quiet button: its words alone, softer than the body ink, raised under the pointer.
        .btnPushFlat_Text           = p.softText
        .btnPushFlat_Border         = .transparent
        .btnPushFlat_Bk             = .transparent
        .btnPushFlat_PressedText    = p.text
        .btnPushFlat_PressedBorder  = .transparent
        .btnPushFlat_PressedBk      = pressed
        .btnPushFlat_HotText        = p.text
        .btnPushFlat_HotBorder      = .transparent
        .btnPushFlat_HotBk          = p.raised
        .btnPushFlat_DisabledText   = disabled
        .btnPushFlat_DisabledBorder = .transparent
        .btnPushFlat_DisabledBk     = .transparent

        // The default action and the strong action are both the primary action: one because the
        // keyboard says so and one because the surface does. They differ in weight — a strong
        // button sets its label bold — and a surface shows one or the other, never both.
        .btnPushDefault_Text           = signature.onGround
        .btnPushDefault_Border         = signature.ground
        .btnPushDefault_Bk             = signature.ground
        .btnPushDefault_PressedText    = signature.onGround
        .btnPushDefault_PressedBorder  = groundPressed
        .btnPushDefault_PressedBk      = groundPressed
        .btnPushDefault_HotText        = signature.onGround
        .btnPushDefault_HotBorder      = groundHot
        .btnPushDefault_HotBk          = groundHot
        .btnPushDefault_DisabledText   = disabled
        .btnPushDefault_DisabledBorder = faintLine
        .btnPushDefault_DisabledBk     = .transparent

        // An icon button is a soft glyph that earns the raised ground under the pointer.
        .btnIcon_Icon         = p.softText
        .btnIcon_Text         = p.softText
        .btnIcon_Bk           = .transparent
        .btnIcon_DisabledIcon = disabled
        .btnIcon_DisabledText = disabled
        .btnIcon_DisabledBk   = .transparent
        .btnIcon_PressedIcon  = p.text
        .btnIcon_PressedText  = p.text
        .btnIcon_PressedBk    = pressed
        .btnIcon_HotIcon      = p.text
        .btnIcon_HotText      = p.text
        .btnIcon_HotBk        = p.raised

        // A checked tool is chosen, so it is Arc: the selection ground, an Arc glyph, and a faint
        // Arc ring that keeps the cell an object on any ground. An indicator on one edge is a
        // two-pixel Arc rule, the same mark as the underline of the active tab.
        .btnIcon_CheckedIcon         = alternate.mark
        .btnIcon_CheckedText         = alternate.mark
        .btnIcon_CheckedBk           = .transparent
        .btnIcon_CheckedMark         = p.selection
        .btnIcon_CheckedHotIcon      = alternate.mark
        .btnIcon_CheckedHotText      = alternate.mark
        .btnIcon_CheckedHotBk        = p.raised
        .btnIcon_CheckedHotMark      = p.selection
        .btnIcon_CheckedPressedIcon  = alternate.mark
        .btnIcon_CheckedPressedText  = alternate.mark
        .btnIcon_CheckedPressedBk    = pressed
        .btnIcon_CheckedPressedMark  = pressed
        .btnIcon_CheckedDisabledIcon = disabled
        .btnIcon_CheckedDisabledText = disabled
        .btnIcon_CheckedDisabledBk   = .transparent
        .btnIcon_CheckedDisabledMark = p.raised
        .btnIcon_CheckedRing         = chosenRing
        .btnIcon_CheckedRule         = alternate.mark

        .btnIcon_CheckedFrameBk             = p.selection
        .btnIcon_CheckedFrameHotBk          = p.selection
        .btnIcon_CheckedFramePressedBk      = pressed
        .btnIcon_CheckedFrameDisabledBk     = .transparent
        .btnIcon_CheckedFrameBorder         = chosenRing
        .btnIcon_CheckedFrameHotBorder      = alternate.mark
        .btnIcon_CheckedFramePressedBorder  = alternate.mark
        .btnIcon_CheckedFrameDisabledBorder = p.line

        .label_Text         = p.text
        .label_TextLight    = p.softText
        .label_TextFaint    = p.faintText
        .label_DisabledText = disabled
        .label_Icon         = p.softText
        .label_DisabledIcon = disabled

        // Off is a ring of the stronger rule; on is an Arc box carrying a check in the ink Arc
        // carries. Hovering an unchecked box only strengthens its ring.
        .btnCheck_Text              = p.text
        .btnCheck_Border            = strongLine
        .btnCheck_Mark              = .transparent
        .btnCheck_Bk                = .transparent
        .btnCheck_PressedText       = p.text
        .btnCheck_PressedBorder     = p.faintText
        .btnCheck_PressedMark       = alternate.onGround
        .btnCheck_PressedBk         = p.raised
        .btnCheck_HotText           = p.text
        .btnCheck_HotBorder         = p.faintText
        .btnCheck_HotMark           = alternate.onGround
        .btnCheck_HotBk             = .transparent
        .btnCheck_DisabledText      = disabled
        .btnCheck_DisabledBorder    = faintLine
        .btnCheck_DisabledMark      = p.ground
        .btnCheck_DisabledBk        = .transparent
        .btnCheck_CheckedText       = p.text
        .btnCheck_CheckedBk         = alternate.ground
        .btnCheck_CheckedBorder     = alternate.ground
        .btnCheck_CheckedMark       = alternate.onGround
        .btnCheck_CheckedHotBk      = arcHot
        .btnCheck_CheckedDisabledBk = disabled

        // A chosen radio button is an Arc ring around an Arc dot.
        .btnRadio_CheckedBorder  = alternate.mark
        .btnRadio_CheckedMark    = alternate.mark
        .btnRadio_CheckedHotMark = shiftState(alternate.mark, StrongHotShift)

        .toolTip_Bk     = p.tip.ground
        .toolTip_Border = p.tip.mark
        .toolTip_Text   = p.tip.onGround

        // Keep the hue the palette chose, and move it until it reads on the note. The same rule
        // the syntax palette follows against the editor ground: a reader has learned what a link
        // means, and a tip is not where that changes.
        .toolTip_Link    = p.link
        .toolTip_HotLink = shiftState(p.link, StrongHotShift)
        .toolTip_Rich1   = p.rich1
        .toolTip_Rich2   = p.rich2
        .toolTip_Rich3   = p.rich3
        .toolTip_Link.ensureContrast(.toolTip_Bk, LinkContrast)
        .toolTip_HotLink.ensureContrast(.toolTip_Bk, LinkContrast)
        .toolTip_Rich1.ensureContrast(.toolTip_Bk)
        .toolTip_Rich2.ensureContrast(.toolTip_Bk)
        .toolTip_Rich3.ensureContrast(.toolTip_Bk)

        // A link is Arc and not the signature: the signature says "this is the thing to do here",
        // and a link says "this is somewhere else".
        .url_Text    = .link
        .url_HotText = shiftState(.link, StrongHotShift)
        .url_HotText.ensureContrast(p.ground, LinkContrast)

        // A field is the surface with a hairline ring. Hover strengthens the ring; the focus
        // replaces it with two pixels of what acts, and a rejected value with two of critical.
        .edit_Border         = p.line
        .edit_FocusBorder    = signature.mark
        .edit_HotBorder      = strongLine
        .edit_DisabledBorder = faintLine
        .edit_Bk             = p.surface
        .edit_DisabledBk     = .transparent
        .edit_ErrorBk        = p.surface
        .edit_HotBk          = p.surface
        .edit_FocusBk        = p.surface
        .edit_Note           = p.faintText
        .edit_Text           = p.text
        .edit_TextUnit       = p.faintText
        .edit_DisabledText   = disabled
        .edit_SelectedBk     = p.selection
        .edit_ErrorBorder    = critical.mark
        .edit_Caret          = signature.mark

        // Selected code keeps the color its lexer gave it — that is what makes a selection
        // readable in an editor — so the selection is a ground and nothing else.
        .richEdit_Bk             = p.ground
        .richEdit_TextSpecial    = p.faintText
        .richEdit_Text           = p.text
        .richEdit_SelText        = .transparent
        .richEdit_SelTextNoFocus = .transparent
        .richEdit_SelBk          = p.selection
        .richEdit_SelBkNoFocus   = p.raised
        .richEdit_Caret          = signature.mark
        .richEdit_CurLineBorder  = p.line

        // A switch is off on the stronger rule with a soft knob, and on in Arc with a white knob.
        .btnToggle_OffBorder        = .transparent
        .btnToggle_OffMark          = p.softText
        .btnToggle_OffBk            = strongLine
        .btnToggle_OffHotBorder     = .transparent
        .btnToggle_OffHotMark       = p.text
        .btnToggle_OffHotBk         = strongLine
        .btnToggle_OffPressedBorder = .transparent
        .btnToggle_OffPressedMark   = p.text
        .btnToggle_OffPressedBk     = p.faintText
        .btnToggle_OnBorder         = .transparent
        .btnToggle_OnMark           = Knob
        .btnToggle_OnBk             = alternate.ground
        .btnToggle_OnHotBorder      = .transparent
        .btnToggle_OnHotMark        = Knob
        .btnToggle_OnHotBk          = arcHot
        .btnToggle_OnPressedBorder  = .transparent
        .btnToggle_OnPressedMark    = Knob
        .btnToggle_OnPressedBk      = shiftState(alternate.ground, StrongPressedShift)
        .btnToggle_DisabledBorder   = .transparent
        .btnToggle_DisabledMark     = p.ground
        .btnToggle_DisabledBk       = p.raised

        // A slider is a hairline track on the raised ground, filled in Arc, with a white knob.
        .slider_BkLeft            = p.raised
        .slider_BkMiddle          = p.raised
        .slider_BkRight           = p.raised
        .slider_HilightBk         = alternate.ground
        .slider_Mark              = Knob
        .slider_MarkBorder        = strongLine
        .slider_HotMark           = Knob
        .slider_PressedMark       = shiftState(Knob, StrongHotShift)
        .slider_DisabledMark      = disabled
        .slider_DisabledBk        = p.raised
        .slider_DisabledHilightBk = disabled
        .slider_StepBk            = strongLine
        .slider_HilightStepBk     = alternate.ground
        .slider_HotStepBk         = p.faintText

        .circular_Bk             = .transparent
        .circular_DisabledBk     = .transparent
        .circular_Circle         = p.raised
        .circular_DisabledCircle = p.line
        .circular_Mark           = alternate.mark
        .circular_HotMark        = shiftState(alternate.mark, StrongHotShift)
        .circular_PressedMark    = shiftState(alternate.mark, StrongPressedShift)
        .circular_DisabledMark   = disabled
        .circular_Step           = p.faintText
        .circular_DisabledStep   = p.line
        .circular_RangeArc       = alternate.mark

        // Tabs are words: faint at rest, the active one in body ink over a two-pixel Arc underline.
        // A round bar is a segment group: a raised frame with the chosen segment on its own ground.
        .tabItem_SelectedText             = p.text
        .tabItem_HotText                  = p.softText
        .tabItem_Text                     = p.faintText
        .tabItem_FlatSelected             = alternate.mark
        .tabItem_FlatHot                  = .transparent
        .tabItem_RoundSelected            = p.segment
        .tabItem_RoundLift                = segmentLifted ? p.shadow.withAlpha(SegmentLiftAlpha) : .transparent
        .tabItem_RoundHot                 = .transparent
        .tabItem_ButtonSelected           = p.segment
        .tabItem_ButtonHot                = p.raised
        .tabItem_PushButtonSelected       = p.selection
        .tabItem_PushButtonSelectedText   = alternate.mark
        .tabItem_PushButtonSelectedBorder = chosenRing
        .tabItem_PushButtonHot            = p.raised
        .tabItem_PushButtonHotText        = p.text
        .tabItem_PushButtonHotBorder      = strongLine
        .tabItem_PushButtonText           = p.text
        .tabItem_PushButtonBk             = .transparent
        .tabItem_PushButtonBorder         = p.line
        .tabBar_FlatBk                    = .transparent
        .tabBar_FlatLine                  = p.line
        .tabBar_RoundBk                   = p.raised
        .tabView_FlatBk                   = .transparent
        .tabView_RoundBk                  = p.surface

        // A menu is a floating surface with a hairline ring. Its entry under the pointer is
        // chosen, so it is the selection ground; a check is Arc, a shortcut and a chevron faint.
        .menuPopup_Bk         = p.surface
        .menuPopup_Border     = p.line
        .menuPopup_Shadow     = p.shadow
        .menuPopup_Separator  = p.line
        .menuBar_Bk           = p.ground
        .menuBar_Border       = p.line
        .menuBar_SelectedBk   = p.selection
        .menuBar_SelectedText = p.text

        .popupItem_Text                  = p.text
        .popupItem_RightText             = p.faintText
        .popupItem_DisabledText          = disabled
        .popupItem_HotText               = p.text
        .popupItem_HotRightText          = p.faintText
        .popupItem_HotBk                 = p.selection
        .popupItem_Marker                = alternate.mark
        .popupItem_HotMarker             = alternate.mark
        .popupItem_DisabledMarker        = disabled
        .popupItem_SubmenuMarker         = p.faintText
        .popupItem_HotSubmenuMarker      = p.softText
        .popupItem_DisabledSubmenuMarker = disabled
        .popupItem_Heading               = p.faintText

        // An option sheet is read row by row, like a menu, so its hovered row is the same ground.
        .optionSheet_HotBk      = p.selection
        .optionSheet_Marker     = alternate.mark
        .optionSheet_StepBorder = p.line

        // A scroll bar is furniture: a thin thumb of a stronger grey, on a raised track only while
        // the reader engages with it.
        .scrollBar_Bk         = .transparent
        .scrollBar_HotBk      = p.raised
        .scrollBar_DisabledBk = .transparent
        .scrollBar_Box        = strongLine
        .scrollBar_HotBox     = p.faintText
        .scrollBar_PressedBox = p.softText

        // A combo box is a field: the same ring, and the focus ring while its list is open.
        .comboBox_Border         = p.line
        .comboBox_HotBorder      = strongLine
        .comboBox_DisabledBorder = faintLine
        .comboBox_SelectedBorder = signature.mark
        .comboBox_Bk             = p.surface
        .comboBox_HotBk          = p.surface
        .comboBox_DisabledBk     = .transparent
        .comboBox_SelectedBk     = p.surface
        .comboBox_Text           = p.text
        .comboBox_HotText        = p.text
        .comboBox_DisabledText   = disabled
        .comboBox_SelectedText   = p.text

        .popupList_Separator    = p.line
        .popupList_HotBk        = p.selection
        .popupList_Text         = p.text
        .popupList_HotText      = p.text
        .popupList_CheckMark    = alternate.mark
        .popupList_HotCheckMark = alternate.mark

        .frameWnd_SmallShadow    = p.shadow
        .frameWnd_Border         = p.line
        .frameWnd_PopupBorder    = p.line
        .frameWnd_FocusBorder    = signature.mark
        .frameWnd_DisabledBorder = p.line
        .frameWnd_Bk             = p.surface
        .frameWnd_DisabledBk     = p.surface
        .frameWnd_FocusBk        = p.surface

        // A row is raised under the pointer and chosen on the selection ground, focused or not.
        .listItem_FocusSelectedBk   = p.selection
        .listItem_FocusSelectedText = p.text
        .listItem_SelectedBk        = p.selection
        .listItem_SelectedText      = p.text
        .listItem_HotBk             = p.raised
        .listItem_DisabledText      = disabled
        .listItem_Text              = p.text
        .listItem_Separator         = p.faintText
        .listItem_AlternateBk       = p.veil.withAlpha(AlternateAlpha)
        .listItem_Line              = p.line
        .listItem_Expand            = p.faintText

        // A header is faint labels over a hairline, with no band behind them.
        .headerItem_DisabledText = disabled
        .headerItem_HotText      = p.softText
        .headerItem_HotBk        = .transparent
        .headerItem_ClickedBk    = p.raised
        .headerItem_Text         = p.faintText
        .headerItem_Separator    = p.line
        .header_Bk               = .transparent

        .splitView_TitleBk = p.ground
        .splitView_Bar     = p.line
        .splitView_BarHot  = strongLine

        .progressBar_Border         = .transparent
        .progressBar_Bk             = p.raised
        .progressBar_Mark           = alternate.ground
        .progressBar_DisabledBorder = .transparent
        .progressBar_DisabledBk     = p.raised
        .progressBar_DisabledMark   = disabled

        .palPicker_Border      = p.line
        .palPicker_HotBorder   = strongLine
        .palPicker_CheckedRing = alternate.mark

        .colorPicker_Border    = p.line
        .colorPicker_BackAlpha = p.surface
        .colorPicker_Mark      = p.text

        .imageRect_Fg = Argb.White

        .spinner_Track = p.raised
        .spinner_Mark  = alternate.mark

        .embInfo_CriticalBk      = critical.ground
        .embInfo_CriticalText    = critical.onGround
        .embInfo_CriticalMark    = critical.mark
        .embInfo_InformationBk   = info.ground
        .embInfo_InformationText = info.onGround
        .embInfo_InformationMark = info.mark
        .embInfo_MessageBk       = caution.ground
        .embInfo_MessageText     = caution.onGround
        .embInfo_MessageMark     = caution.mark

        .prop_FocusBk     = p.selection
        .prop_FocusBorder = signature.mark
        .prop_HotBk       = p.raised
        .prop_HotBorder   = .transparent
        .prop_GridBorder  = p.line
        .prop_GridColumn  = p.line
        .prop_SectionBk   = .transparent
        .prop_CategBk     = .transparent
    }

    // Applies Encre, the dark theme.
    mtd setDark()
    {
        .apply(encrePalette())
    }

    // Applies Papier, the light theme.
    mtd setLight()
    {
        .apply(papierPalette())
    }

    // Returns Encre, the dark palette: a slightly cold graphite, Voltage for what acts and Arc
    // for what is chosen.
    func encrePalette()->ThemePalette
    {
        let ground: Color = 0xFF17181C
        let text:   Color = 0xFFECEDF0

        var result: #returntype
        result.ground  = ground
        result.surface = 0xFF1F2026
        result.raised  = 0xFF2A2C33
        result.line    = 0xFF33353D

        result.text      = text
        result.softText  = 0xFFA3A6B0
        result.faintText = 0xFF737783

        // The primary action is a Voltage block carrying the ground's ink, and a checked box is an
        // Arc box carrying the same ink.
        result.signature = ThemeTone.from(Voltage, ground)
        result.alternate = ThemeTone.from(Arc, ground)

        result.link      = 0xFF7DD3FC
        result.selection = 0x2938BDF8     // Arc at 16 percent.
        result.highlight = 0x38F7F900     // Voltage at 22 percent.
        result.segment   = result.selection

        result.currentMatch = ThemeTone.from(Voltage, ground)
        result.tip.mark     = result.line
        result.tip.ground   = result.surface
        result.tip.onGround = text

        // The status tones point in their own hue and tint a ground at twelve percent of it.
        result.critical.mark     = 0xFFFF6B6B
        result.critical.ground   = 0x1FFF6B6B
        result.critical.onGround = text
        result.caution.mark      = 0xFFF2B544
        result.caution.ground    = 0x1FF2B544
        result.caution.onGround  = text
        result.info.mark         = Arc
        result.info.ground       = 0x1F38BDF8
        result.info.onGround     = text

        result.rich1 = 0xFFFF8A8A
        result.rich2 = 0xFF8FD48F
        result.rich3 = 0xFF7DD3FC

        result.veil   = 0xFFFFFFFF
        result.shadow = 0x8C000000
        return result
    }

    // Returns Papier, the light palette: warm paper, ink for what acts, a deepened Arc for what
    // is chosen.
    func papierPalette()->ThemePalette
    {
        let paper: Color = 0xFFF5F4F0
        let ink:   Color = 0xFF1A1B1E
        let arc:   Color = 0xFF0A7FB5
        let white: Color = 0xFFFFFFFF

        var result: #returntype
        result.ground  = paper
        result.surface = white
        result.raised  = 0xFFEBEAE5
        result.line    = 0xFFE0DED7

        result.text      = ink
        result.softText  = 0xFF55585F
        result.faintText = 0xFF72757C

        // Voltage is never written on paper: the primary action is the same button turned over,
        // an ink block carrying paper, and Arc is deepened so that it reads as a word.
        result.signature = ThemeTone.from(ink, paper)
        result.alternate = ThemeTone.from(arc, white)

        result.link      = 0xFF0A6FA0
        result.selection = 0xFFDCEFFA
        result.highlight = 0xFFFBF68A

        // On paper the chosen segment is lifted white rather than washed in Arc.
        result.segment = result.surface

        // The current occurrence keeps the highlight ground and is underlined in ink, and a tip
        // is ink with paper text: a white note on white paper would vanish.
        result.currentMatch.mark     = ink
        result.currentMatch.ground   = result.highlight
        result.currentMatch.onGround = ink
        result.tip = ThemeTone.from(ink, paper)

        result.critical.mark     = 0xFFC42B2B
        result.critical.ground   = 0xFFFBE9E9
        result.critical.onGround = ink
        result.caution.mark      = 0xFFA36A00
        result.caution.ground    = 0xFFFBF1DC
        result.caution.onGround  = ink
        result.info.mark         = result.alternate.mark
        result.info.ground       = result.selection
        result.info.onGround     = ink

        result.rich1 = 0xFFB42020
        result.rich2 = 0xFF1E7A32
        result.rich3 = 0xFF0A6FA0

        result.veil   = 0xFF000000
        result.shadow = 0x29000000
        return result
    }
}
