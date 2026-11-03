#global if #command == Swag.CompilerCommand.Test
#global internal

using Swag, Core, Pixel

const IconButtonHeadless_Command = "IconButtonHeadless.Command"

var IconButtonHeadlessPressedCount: u32
var IconButtonHeadlessCheckCount:   u32

func iconButtonHeadlessPressed(_: *Button)
{
    IconButtonHeadlessPressedCount += 1
}

func iconButtonHeadlessChecked(_: *IconButton)
{
    IconButtonHeadlessCheckCount += 1
}

func iconButtonHeadlessReset()
{
    IconButtonHeadlessPressedCount = 0
    IconButtonHeadlessCheckCount   = 0
}

// A plain icon button posts a command and fires sigPressed on click.

// A Toggle button flips its checked state on every click.

// A radio button can only be set, never unset, by user activation.

// Programmatic checked-state changes support both stateful modes and remain silent.

// Space and Enter activate a focused toggle with the same state, signal, and command contract as a click.

// Number of pixels painted in one exact color.
func iconButtonColorCount(image: const *Image, color: Color)->s32
{
    var result = 0
    for y in cast(s32, image.height)
    {
        for x in cast(s32, image.width)
        {
            if image.pixelColor(x, y).argb == color.argb do
                result += 1
        }
    }

    return result
}

// A checked button draws the indicator its placement asks for, and none at all when it asks
// for none.
//
// An indicator on one edge is the two-pixel Arc rule of a tab underline. Drawn under a color
// swatch, a field of a form, or a preset cell painted in the user's own colors, it would read as
// one more thing painted in the cell, which is why the two indicator-less placements draw none.

// The checked frame is drawn on the shape the button has.
//
// A rectangular tool takes the control corner like a rounded one. The frame and the focus ring
// have to follow that corner, or either mark crosses the fill at the corners — which leaves the
// corner pixel of the cell on the ground it stands on.

// A checked tool is written in Arc in both themes, and never in the ink of a fill.

// The two indicator-less placements differ by what they leave the state colors saying: `None`
// reads as pressed, `Ink` keeps the checked ink so the glyph itself carries the state.

// Hiding a button resets both its pointer state and its animated overlay state.

// Disabling a button keeps it in the layout, but still drops transient input/paint state.

// An icon button answers what its content needs, so a longer wording widens the button
// instead of being crowded by it.

// A compact toolbar menu centers icon, wording, and disclosure as one horizontal group. Its
// outer air and both inner gaps share one rhythm instead of tightening toward either edge.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 68)

    let metrics = &host.theme.metrics
    Swag.assert(metrics.btnIcon_Padding == metrics.btnIcon_SpacingTextH)
    Swag.assert(metrics.btnIcon_SpacingArrowH == metrics.btnIcon_SpacingTextH)

    let btn = IconButton.create(&host.root, host.theme.icon(.Redo, 18), {20, 16, 120, 36}, flags: .CenterContent)
    btn.setArrowPosition(.RightDownward)
    let iconOnly = btn.itf.measureContent({160, 68})
    Swag.assert(iconOnly.x == 2 * metrics.btnIcon_Padding + 18 + metrics.btnIcon_SpacingArrowH + metrics.btnIcon_ArrowSize)
    Swag.assert(iconOnly.y == 2 * metrics.btnIcon_Padding + 18)

    btn.setText("View")
    btn.setTextPosition(.Right)
    let withText = btn.itf.measureContent({160, 68})
    Swag.assert(withText.x > iconOnly.x + metrics.btnIcon_SpacingTextH)
    Swag.assert(withText.y == iconOnly.y)

    var image = host.renderSettled(&host.root)
    Pixel.Testing.assertImageGolden(&image, "iconbutton.menu-arrow")
}
