#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// The history label that exposed the clipping bug keeps one physical pixel beyond its measured
// run at fractional DPI, so the accented final glyph cannot land on the half-open clip edge.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(420, 200, 1.5)

    let btn = PushButton.create(&host.root, "Files", {20, 20, 100, 30})
    let lbl = showTip(btn, "Fichiers à côté de celui-ci")
    let tip = unwrap host.app.toolTip.current
    assertPassiveAndFits(tip, lbl)

    Swag.assert(lbl.maxLines == 0)

    let rendered = host.renderSettled(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&rendered, "tooltip.history-fractional")
}

// The shapes a tip can take, rendered.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(460, 320)

    let btn = PushButton.create(&host.root, "Library", {20, 20, 100, 30})

    discard showTip(btn, "Refresh")
    let short = host.renderSettled(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&short, "tooltip.short")

    discard showTip(btn, "Afficher la bibliothèque de captures et retrouver les images enregistrées pendant la session")
    let wrapped = host.renderSettled(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&wrapped, "tooltip.wrapped")

    let long = longAnnotation()
    discard showTip(btn, long.toString())
    let truncated = host.renderSettled(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&truncated, "tooltip.truncated")

    discard showTip(btn, "Read <b>the guide</b> at <url>swag-lang.org</url>, or ask on <p1>Discord</p>")
    let rich = host.renderSettled(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&rich, "tooltip.rich")
}
