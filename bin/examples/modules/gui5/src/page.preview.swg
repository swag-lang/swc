using Core, Gui, Pixel

func createPreviewPage(parent: *Wnd)
{
    let layout = getPagePanelLayout(parent)
    let left = createPanel(parent, "Selected color card", "The selected color is rendered with checkerboard alpha, automatic contrast text and complement accent.", layout.left)
    discard createPreview(left, {18, 86, layout.left.width - 36, layout.left.height - 104}, &onLivePreviewEvent)

    let right = createPanel(parent, "Derived colors", "Hue rotation, complementary, saturation and grayscale helpers become real UI swatches.", layout.right)
    discard createPreview(right, {18, 86, layout.right.width - 36, layout.right.height - 104}, &onDerivedPreviewEvent)

    let bottom = createPanel(parent, "Contrast and transparency", "The same selected color drives contrast text and alpha compositing previews.", layout.bottom)
    discard createPreview(bottom, {18, 86, layout.bottom.width - 36, layout.bottom.height - 104}, &onContrastPreviewEvent)
}
