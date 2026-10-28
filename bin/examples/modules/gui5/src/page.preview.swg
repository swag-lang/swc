using Core, Gui, Pixel

func createPreviewPage(parent: *Wnd)
{
    let layout = getPagePanelLayout(parent)
    let left   = createPanel(parent,
                             "Selected color card",
                             "The selected color is rendered with checkerboard alpha, automatic contrast text and complement accent.",
                             layout.left)
    discard createPreview(left, &onLivePreviewEvent)

    let right = createPanel(parent,
                            "Derived colors",
                            "Hue rotation, complementary, saturation and grayscale helpers become real UI swatches.",
                            layout.right)
    discard createPreview(right, &onDerivedPreviewEvent)

    let bottom = createPanel(parent,
                             "Contrast and transparency",
                             "The same selected color drives contrast text and alpha compositing previews.",
                             layout.bottom)
    discard createPreview(bottom, &onContrastPreviewEvent)
}
