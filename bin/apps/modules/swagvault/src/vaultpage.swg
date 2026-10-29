using Core, Gui, Pixel

// The column every page of the window stands in.
//
// A page is a measured column centred in the window, not a card: the window's ground is the page,
// and only space separates its parts. The list rows and the unfolded vault reach a little past
// the column on both sides, so their words line up with the title while their grounds keep air
// around them.
const PageColumnWidth = 584'f32     // Width of the column the words of a page stand in.
const PageGutter      = 32'f32      // Least air kept between the column and a window edge.
const PageTop         = 64'f32      // Distance from the top of the window to the head of a page.
const PageFoot        = 48'f32      // The foot of the window the hint line stands in; a centred column is centred above it.
const ListTop         = 64'f32      // Distance from the strip to the title of the list, which has no way back above it.
const PageTitleSize   = 40'u32      // Size of a page title.
const PageHeadGap     = 32'f32      // Air between the head of a page and what it introduces.
const RowOutset       = 28'f32      // How far a row's ground reaches past the column on each side.

// The head of a page reached from the list: the way back, the title, and the sentence under it.
struct PageHead
{
    late
    {
        back:  *IconButton
        title: *Label
    }

    help: *Label?
}

impl PageHead
{
    // Creates the head at the top of `column`. A null `help` leaves the title alone.
    func create(column: *StackLayoutCtrl, title: string, help: string?)->PageHead
    {
        let back = createQuietLink(column, appStrings().ui_BackToVaults)

        let titleLabel = createPageTitle(column, title)
        titleLabel.margin.y = 16

        var helpLabel: *Label?
        if help
        {
            with let label = Label.create(column, help, {}, null, .WordWrap | .SecondaryText | .AutoHeight)
            {
                .margin.y = 8
                .setTextAlignment(.Left, .Top)
            }

            helpLabel = label
        }

        return PageHead{back, titleLabel, helpLabel}
    }

    // Says the head again in the language now active.
    mtd retranslate(title: string, help: string?)
    {
        .back.setText(appStrings().ui_BackToVaults)
        .title.setText(title)
        if help do
            .help?.setText(help)
    }
}

// Creates the vertical column of a page, empty, for the caller to fill and [[placePageColumn]] to place.
func createPageColumn(page: *Wnd)->*StackLayoutCtrl
{
    with let result = StackLayoutCtrl.create(page, .Top)
    {
        .backgroundStyle = .Transparent
        .spacing         = 0
    }

    return result
}

// Creates the title of a page: a name set large and heavy, as tall as its own line box.
func createPageTitle(parent: *Wnd, title: string)->*Label
{
    let font        = parent.theme().createDefaultFont(PageTitleSize, .Bold)
    with let result = Label.create(parent, title, {0, 0, 0, font.height})
    {
        .setTextAlignment(.Left, .Top)
        .style.setFont(font, .Regular)
    }

    return result
}

// Creates a quiet word that acts: its words alone, a ground only under the pointer.
//
// Its words line up with the column it stands in, so the ground it shows under the pointer reaches
// into the margin rather than pushing the words inwards.
func createQuietLink(parent: *Wnd, text: string)->*IconButton
{
    with let result = IconButton.create(parent, {}, Math.Rectangle{0, 0, 0, parent.themeMetrics().btnPush_Height}, flags: .CenterContent)
    {
        .preferredSize.x   = 0     // The width is the words', measured; the button keeps no floor of its own.
        .layoutSpec.alignX = .Start
        .margin.x          = -parent.themeMetrics().btnIcon_Padding
        .setForm(.RoundedRectangle)
        .setText(text)
    }

    return result
}

// Places `column` in `page`: centred across, at the head of the page or, when `centred`, in its
// middle. The column is as tall as what it holds at the width it is given.
func placePageColumn(page: *Wnd, column: *Wnd, centred = false)
{
    let room   = page.clientRect()
    let width  = Math.min(PageColumnWidth, Math.max(0, room.width - 2 * PageGutter))
    let height = Math.ceil(column.measure(Math.Point{width, 0}).preferred.y)

    var top = PageTop
    if centred do
        top = Math.max(PageTop, Math.round((room.height - PageFoot - height) * 0.5))
    column.arrange(Math.Rectangle{Math.round((room.width - width) * 0.5), top, width, height})

    // A new wording can change what the column holds without changing its size.
    column.applyLayout()
}
