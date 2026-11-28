#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// A compact toolbar menu centers icon, wording, and disclosure as one horizontal group. Its
// outer air and both inner gaps share one rhythm instead of tightening toward either edge.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 68)

    let metrics = &host.theme.metrics
    Swag.require(metrics.btnIcon_Padding == metrics.btnIcon_SpacingTextH)
    Swag.require(metrics.btnIcon_SpacingArrowH == metrics.btnIcon_SpacingTextH)

    let btn = IconButton.create(&host.root, host.theme.icon(.Redo, 18), {20, 16, 120, 36}, flags: .CenterContent)
    btn.setArrowPosition(.RightDownward)
    let iconOnly = btn.itf.measureContent({160, 68})
    Swag.require(iconOnly.x == 2 * metrics.btnIcon_Padding + 18 + metrics.btnIcon_SpacingArrowH + metrics.btnIcon_ArrowSize)
    Swag.require(iconOnly.y == 2 * metrics.btnIcon_Padding + 18)

    btn.setText("View")
    btn.setTextPosition(.Right)
    let withText = btn.itf.measureContent({160, 68})
    Swag.require(withText.x > iconOnly.x + metrics.btnIcon_SpacingTextH)
    Swag.require(withText.y == iconOnly.y)

    var image = host.renderSettled(&host.root)
    Pixel.Testing.assertImageGolden(&image, "iconbutton.menu-arrow")
}
