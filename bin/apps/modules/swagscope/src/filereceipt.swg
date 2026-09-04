using Core, Gui

const ViewerFileReceiptWidth  = 480.0
const ViewerFileReceiptHeight = 76.0
const ViewerFileReceiptInset  = 24.0
const ViewerFileReceiptMinDuration: Time.Duration = 350'ms

// A short-lived attachment preview that confirms a file dropped from another application.
//
// The window owns classification, so this surface only answers the immediate question a drop
// raises: which file did Swag Scope receive? It stays above an outgoing document without
// obscuring it, then gives way to the viewer that opens the file.
struct ViewerFileReceipt
{
    using wnd: Wnd

        late
    {
        card:        *Wnd
        iconLabel:   *Label
        nameLabel:   *Label
        statusLabel: *Label
    }
}

impl IWnd for ViewerFileReceipt
{
    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        discard evt
        if .card == null do
            return
        .layoutCard()
    }
}

impl ViewerFileReceipt
{
    func create(parent: *Wnd)->*ViewerFileReceipt
    {
        let result = Wnd.create'ViewerFileReceipt(parent, "scope.drop.receipt")
        result.dockStyle       = .Center
        result.backgroundStyle = .Transparent
        result.wndFlags        |= WndFlags.TopMost | WndFlags.Disabled

        with result.card = Wnd.create'Wnd(result, {0, 0, ViewerFileReceiptWidth, ViewerFileReceiptHeight})
        {
            .backgroundStyle = .InformationPanel
        }

        with result.iconLabel = Label.create(result.card, "", {0, 0, 40, ViewerFileReceiptHeight})
        {
            .setIconAlignment(.Center, .Center)
        }

        with result.nameLabel = Label.create(result.card, "", {0, 0, 0, 24}, null, .Ellipsis)
        {
            .style.setFont(result.theme().createDefaultFontFS(13), .Regular)
            .setTextAlignment(.Left, .OpticalCenter)
        }

        with result.statusLabel = Label.create(result.card, appStrings().ui_DropAccepted, {0, 0, 0, 20}, null, .SecondaryText | .Ellipsis)
        {
            .setTextAlignment(.Left, .OpticalCenter)
        }

        result.layoutCard()
        result.refreshTheme()
        result.hide()
        return result
    }

    // Publishes the file name before classification starts, when the desktop drag has only just
    // returned. The path remains available as a tooltip without turning the receipt into a path
    // field the reader has to parse.
    mtd showFile(fileName: string)
    {
        .nameLabel.setText(Path.fileName(fileName) orelse fileName)
        .nameLabel.toolTip = fileName
        .statusLabel.setText(appStrings().ui_DropAccepted)
        .layoutCard()
        .show()
        .bringToFront()
    }

    mtd retranslate()
    {
        .statusLabel.setText(appStrings().ui_DropAccepted)
    }

    mtd refreshTheme()
    {
        .iconLabel.setIcon(.theme().icon(.OpenFile, 32))
        .iconLabel.setIconColor(.themeColors().label_TextFaint)
    }

    // The transparent host covers the document while the panel itself stays attachment-sized.
    // At narrow widths it gives the document its regular outer air before its label ellipsizes.
    private mtd layoutCard()
    {
        let client = .clientRect()
        let width  = Math.max(Math.min(ViewerFileReceiptWidth, client.width - 2 * ViewerFileReceiptInset), 0)
        let left   = client.horzCenter() - width * 0.5
        let textX  = 64.0
        let textW  = Math.max(width - textX - 16, 0)

        .card.setPosition({left, client.vertCenter() - ViewerFileReceiptHeight * 0.5, width, ViewerFileReceiptHeight}, computeLayout: false)
        .iconLabel.setPosition({12, 0, 40, ViewerFileReceiptHeight}, computeLayout: false)
        .nameLabel.setPosition({textX, 12, textW, 24}, computeLayout: false)
        .statusLabel.setPosition({textX, 36, textW, 20}, computeLayout: false)
    }
}
