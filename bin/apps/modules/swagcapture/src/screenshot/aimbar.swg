using Core, Pixel

// The row of the aiming overlay, after the charter picture: what the capture keeps, whether the
// cursor is in it and whether a recording counts down, then the one action, in Voltage.
//
// The overlay holds the pointer for itself, so the row is painted and hit-tested by the overlay
// rather than made of controls. Kinds of capture not built yet are listed already, out of reach,
// so the row keeps its shape when they come.
const AimBarHeight    = 40.0     // Height of the row.
const AimBarPadding   = 5.0      // Air between the edge of the row and its items.
const AimBarGap       = 6.0      // Air between two items.
const AimBarItem      = 30.0     // Height of an item.
const AimBarInset     = 9.0      // Air on each side of the words of an item.
const AimBarTakeLeft  = 13.0     // Air before the words of the action.
const AimBarTakeRight = 16.0     // Air after the words of the action.
const AimBarIcon      = 16.0     // Side of an icon.
const AimBarIconGap   = 8.0      // Air between an icon and its words.
const AimBarSegInset  = 2.0      // Air between the frame of the kinds of capture and a kind.
const AimBarSegText   = 10.0     // Air on each side of the name of a kind of capture.
const AimBarRule      = 16.0     // Height of the rule between two groups.
const AimBarDot       = 4.0      // Radius of the recording dot on the action.
const AimBarZoneGap   = 14.0     // Air between the zone and the row under it.

// What one place of the row does.
enum AimItem
{
    None
    Picture       // Keep a picture.
    Animation     // Record an animation.
    Video         // Record a video; not built yet.
    Sound         // Record sound alone; not built yet.
    Scroll        // Capture a scrolling page; not built yet.
    Cursor        // Whether the cursor is in the capture.
    Countdown     // Whether a recording counts down before it starts.
    Audio         // The sound of a recording; an animation has none.
    Take          // Take the zone.
}

// One place of the row, in the coordinates of the row.
struct AimBarPart
{
    item: AimItem
    rect: Math.Rectangle
}

struct AimBar
{
    late main: *MainWnd
    rect:      Math.Rectangle     // The row, in logical overlay units; empty when it is not shown.
    parts:     Array'AimBarPart
    segFrame:  Math.Rectangle     // Frame of the kinds of capture, in the coordinates of the row.
    rules:     [2] f32            // Places of the two rules, in the coordinates of the row.
    reasonX:   f32                // Where the reason the sound is out of reach is written; zero for none.
    hot:       AimItem            // The item under the pointer.
    pressed:   AimItem            // The item the left button went down on.
}

impl AimBar
{
    // Returns whether `item` can be acted on now.
    mtd const isEnabled(item: AimItem)->bool
    {
        switch item
        {
        case .Picture, .Animation, .Cursor: return true
        case .Countdown: return g_CaptureMedia == .Animation
        case .Take:      return not getGrabRect().isEmpty()
        }

        return false
    }

    // Returns whether `item` is chosen or on.
    mtd const isOn(item: AimItem)->bool
    {
        switch item
        {
        case .Picture:   return g_CaptureMedia == .Picture
        case .Animation: return g_CaptureMedia == .Animation
        case .Cursor:    return .main.captureOptions.captureCursor
        case .Countdown: return .main.captureOptions.recordCountdown and g_CaptureMedia == .Animation
        }

        return false
    }

    // Returns the item at `pos`, in logical overlay units, or `None`.
    mtd const hitTest(pos: Math.Point)->AimItem
    {
        if not .rect.contains(pos) do
            return .None
        let local = Math.Point{pos.x - .rect.x, pos.y - .rect.y}
        for part in .parts where part.rect.contains(local) do
            return part.item
        return .None
    }

    // Acts on `item`. Returns true when it takes the zone.
    mtd activate(item: AimItem)->bool
    {
        if not .isEnabled(item) do
            return false

        switch item
        {
        case .Picture:   g_CaptureMedia = .Picture
        case .Animation: g_CaptureMedia = .Animation
        case .Cursor:    .main.captureOptions.captureCursor = not .main.captureOptions.captureCursor
        case .Countdown: .main.captureOptions.recordCountdown = not .main.captureOptions.recordCountdown
        case .Take:      return true
        }

        return false
    }

    // Lays the row out for `wnd` and returns its width; the parts stand from the left edge of the
    // row, which [[AimBar.place]] then puts on the screen.
    mtd layout(wnd: *Wnd)->f32
    {
        .parts.clear()
        let font = labelFont(wnd)
        var x    = AimBarPadding
        let top  = (AimBarHeight - AimBarItem) * 0.5

        // The kinds of capture, as segments in one frame.
        let segX = x
        x += AimBarSegInset
        for item in [AimItem.Picture, .Animation, .Video, .Sound, .Scroll]
        {
            let width = Painter.measureString(label(item), font).width + 2 * AimBarSegText
            .parts.add({item, {x, top + AimBarSegInset, width, AimBarItem - 2 * AimBarSegInset}})
            x += width + AimBarSegInset
        }

        .segFrame = {segX, top, x - segX, AimBarItem}
        x         += AimBarGap

        // The options of the capture, each an icon and its words.
        .rules[0] = x
        x         += 1 + AimBarGap
        for item in [AimItem.Cursor, .Countdown]
        {
            let width = AimBarInset + AimBarIcon + AimBarIconGap + Painter.measureString(label(item), font).width + AimBarInset
            .parts.add({item, {x, top, width, AimBarItem}})
            x += width + AimBarGap
        }

        // The sound, out of reach, and why when the reason is not plain.
        .rules[1] = x
        x         += 1 + AimBarGap
        .parts.add({AimItem.Audio, Math.Rectangle{x, top, AimBarItem, AimBarItem}})
        x        += AimBarItem + AimBarGap
        .reasonX = 0
        if g_CaptureMedia == .Animation
        {
            .reasonX = x - 2
            x        += Painter.measureString(appStrings().ui_AimNoSound, reasonFont(wnd)).width + AimBarGap
        }

        // The action.
        let take  = Painter.measureString(.takeLabel(), takeFont(wnd)).width
        let dot   = g_CaptureMedia == .Animation ? 2 * AimBarDot + AimBarIconGap : 0
        let width = AimBarTakeLeft + dot + take + AimBarTakeRight
        .parts.add({AimItem.Take, {x, top, width, AimBarItem}})
        x += width + AimBarPadding

        return x
    }

    // Places the row of width `width` under `zone`, or over it, or inside it when the screen has no
    // room around it; or, while the zone still follows the pointer, at the foot of the screen the
    // pointer is on. Everything in logical overlay units; `monitor` is the work area the row stays
    // in.
    mtd place(width: f32, zone: Math.Rectangle, monitor: Math.Rectangle, underZone: bool)
    {
        let inset = AimBarZoneGap
        var place = Math.Rectangle{0, 0, width, AimBarHeight}
        if underZone
        {
            place.x = zone.horzCenter() - width * 0.5
            place.y = zone.bottom() + AimBarZoneGap
            if place.bottom() > monitor.bottom() - inset do
                place.y = zone.y - AimBarZoneGap - AimBarHeight
            if place.y < monitor.y + inset do
                place.y = zone.bottom() - AimBarZoneGap - AimBarHeight
        }
        else
        {
            place.x = monitor.horzCenter() - width * 0.5
            place.y = monitor.bottom() - g_App.theme.metrics.floating_Inset - AimBarHeight
        }

        place.x = Math.max(Math.min(place.x, monitor.right() - inset - width), monitor.x + inset)
        place.x = Math.round(place.x)
        place.y = Math.round(place.y)
        .rect   = place
    }

    // Paints the row in `wnd`.
    mtd paint(wnd: *Wnd, painter: *Painter)
    {
        if .rect.isEmpty() do
            return

        let theme   = wnd.theme()
        let colors  = wnd.themeColors()
        let metrics = wnd.themeMetrics()
        let corner  = metrics.corner_Floating
        let origin  = Math.Point{.rect.x, .rect.y}
        let font    = labelFont(wnd)
        let cy      = .rect.vertCenter()

        painter.setParams(.Antialiased)
        theme.drawFloatingShadow(painter, .rect, corner)
        painter.setParams(.Antialiased)
        painter.fillRoundRect(.rect, corner, corner, colors.surface)
        painter.drawRoundRect(.rect, corner, corner, colors.line, metrics.separator_HairlineSize)

        // The frame of the kinds of capture.
        var frame = .segFrame
        frame.offset(origin.x, origin.y)
        painter.fillRoundRect(frame, metrics.corner_Control, metrics.corner_Control, colors.tabBar_RoundBk)

        for part in .parts
        {
            var r = part.rect
            r.offset(origin.x, origin.y)
            let enabled = .isEnabled(part.item)
            let on      = .isOn(part.item)
            let hot     = enabled and .hot == part.item

            switch part.item
            {
            case .Picture, .Animation, .Video, .Sound, .Scroll:
                if on
                {
                    var lift = r
                    lift.y += 1
                    painter.fillRoundRect(lift, metrics.corner_Chip, metrics.corner_Chip, colors.tabItem_RoundLift)
                    painter.fillRoundRect(r, metrics.corner_Chip, metrics.corner_Chip, colors.tabItem_RoundSelected)
                }
                elif hot
                {
                    painter.fillRoundRect(r, metrics.corner_Chip, metrics.corner_Chip, colors.tabItem_RoundHot)
                }

                let ink = on ? colors.text : (enabled ? colors.softText : colors.disabled)
                painter.drawString(r.x + AimBarSegText, font.opticalLineTop(cy), label(part.item), font, ink)

            case .Cursor, .Countdown:
                if on do
                    painter.fillRoundRect(r, metrics.corner_Control, metrics.corner_Control, colors.selection)
                elif hot do
                    painter.fillRoundRect(r, metrics.corner_Control, metrics.corner_Control, colors.raised)

                let ink  = enabled ? colors.text : colors.disabled
                let mark = on ? colors.arc : (enabled ? colors.softText : colors.disabled)
                let icon = part.item == .Cursor ? .main.icon(.Select, AimBarIcon) : theme.icon(.HourGlass, AimBarIcon)
                icon.paint(painter, r.x + AimBarInset, cy - AimBarIcon * 0.5, mark)
                painter.drawString(r.x + AimBarInset + AimBarIcon + AimBarIconGap, font.opticalLineTop(cy), label(part.item), font, ink)

            case .Audio:
                let icon = theme.icon(.Volume, AimBarIcon)
                icon.paint(painter, r.horzCenter() - AimBarIcon * 0.5, cy - AimBarIcon * 0.5, colors.disabled)

            case .Take:
                let fill = enabled ? (hot ? colors.btnPush_StrongHotBk : colors.btnPush_StrongBk) : colors.raised
                let ink  = enabled ? (hot ? colors.btnPush_StrongHotText : colors.btnPush_StrongText) : colors.disabled
                painter.fillRoundRect(r, metrics.corner_Control, metrics.corner_Control, fill)

                var x    = r.x + AimBarTakeLeft
                let bold = takeFont(wnd)
                if g_CaptureMedia == .Animation
                {
                    painter.fillCircle(x + AimBarDot, cy, AimBarDot, ink)
                    x += 2 * AimBarDot + AimBarIconGap
                }

                painter.drawString(x, bold.opticalLineTop(cy), .takeLabel(), bold, ink)
            }
        }

        // The rules between the groups.
        for i in 0 until 2 do
            painter.fillRect({origin.x + .rules[i], cy - AimBarRule * 0.5, 1, AimBarRule}, colors.line)

        // Why the sound is out of reach.
        if .reasonX
        {
            let reason = reasonFont(wnd)
            painter.drawString(origin.x + .reasonX, reason.opticalLineTop(cy), appStrings().ui_AimNoSound, reason, colors.disabled)
        }
    }

    // Returns the words of the action, which name what it starts.
    mtd const takeLabel()->string => g_CaptureMedia == .Animation ? appStrings().ui_AimRecord : appStrings().ui_AimCapture

    // Returns the words naming `item`.
    func label(item: AimItem)->string
    {
        switch item
        {
        case .Picture:   return appStrings().ui_MediaPicture
        case .Animation: return appStrings().ui_MediaAnimation
        case .Video:     return appStrings().ui_MediaVideo
        case .Sound:     return appStrings().ui_MediaSound
        case .Scroll:    return appStrings().ui_MediaScroll
        case .Cursor:    return appStrings().ui_AimCursor
        case .Countdown: return appStrings().ui_AimCountdown
        }

        return ""
    }

    // Returns the face of the words of the row.
    func labelFont(wnd: *Wnd)->*Font => wnd.theme().createDefaultFont(wnd.themeMetrics().defaultFontSize)

    // Returns the face of the reason the sound is out of reach: a caption.
    func reasonFont(wnd: *Wnd)->*Font => wnd.theme().createDefaultFont(wnd.themeMetrics().defaultFontSize - 1)

    // Returns the face of the action.
    func takeFont(wnd: *Wnd)->*Font => wnd.theme().createDefaultFont(wnd.themeMetrics().defaultFontSize, .Bold)
}
