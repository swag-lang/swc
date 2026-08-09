using Core, Gui, Pixel

const CardRadius = 10.0
const BadgeSize  = 24.0

// One tile of the choreography strip.
//
// The card paints nothing animated of its own: the strip moves it with presentation opacity,
// offset, and scale, none of which touch its logical rectangle. That is what the page is there to
// show — the tile is laid out once, and only its image travels.
struct MotionCard
{
    using wnd: Wnd

    rank:   s32             // One-based position in the strip, shown in the badge.
    title:  string = ""     // Short label of the tile.
    detail: string = ""     // Second line, describing what the tile stands for.
}

impl MotionCard
{
    func create(parent: *Wnd, rank: s32, title, detail: string)->*MotionCard
    {
        let result = Wnd.create'MotionCard(parent, {})
        result.backgroundStyle = .Transparent
        result.rank            = rank
        result.title           = title
        result.detail          = detail
        return result
    }
}

impl IWnd for MotionCard
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        let theme   = .theme()
        let rect    = .clientRect()

        painter.fillRoundRect(rect, CardRadius, CardRadius, colors.wnd_Bk)
        painter.drawRoundRect(rect, CardRadius, CardRadius, colors.border, 1)
        painter.fillRoundRect({rect.x + 1, rect.y + 10, 3, rect.height - 20}, 1.5, 1.5, colors.hilight)

        let badgeX = rect.x + 18
        let badgeY = rect.y + 16
        painter.fillRoundRect({badgeX, badgeY, BadgeSize, BadgeSize}, 6, 6, colors.hilight)

        let badgeFont = theme.createDefaultFont(12, .Bold)
        painter.drawStringCenter(badgeX + BadgeSize * 0.5, badgeY + BadgeSize * 0.5, Format.toString("%", .rank), badgeFont, colors.hilightLightContrast)

        let titleFont = theme.createDefaultFont(14, .Bold)
        painter.drawString(rect.x + 18, titleFont.opticalTop(badgeY + BadgeSize + 20, 14), .title, titleFont, colors.label_Text)

        let detailFont = theme.createDefaultFont(12)
        painter.drawString(rect.x + 18, detailFont.opticalTop(badgeY + BadgeSize + 42, 12), .detail, detailFont, colors.label_TextLight)
    }
}
