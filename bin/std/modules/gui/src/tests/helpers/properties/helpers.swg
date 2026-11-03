#global if #command == Swag.CompilerCommand.Test
#global internal

using Swag, Core

func findFieldItem(prop: *Properties, name: string)->*PropertiesItem?
{
    for it in prop.items
    {
        let item = unwrap it
        if item.typeValue.name == name do
            return item
    }

    return null
}

// --- Custom editor registry -------------------------------------------------

struct PropHeadlessAngle
{
    deg: s32 = 45
}

var g_PropAngleEditorCalls: s32

enum PropGoldenChoice
{
    Automatic
    Manual
    Disabled
}

struct PropGoldenData
{
    #[Category("Appearance"), Name("Visible"), Description("Shows the element in the composed scene.")]
    visible: bool = true

    #[Category("Appearance"), Name("Opacity"), SliderMinMax(0, 1)]
    opacity: f32 = 0.75

    #[Category("Appearance"), Name("Tint")]
    tint: Pixel.Color = 0xFF38BDF8

    #[Category("Layout"), Name("Offset")]
    offset: Math.Point = {12, 8}

    #[Category("Layout"), Name("Mode"), Properties.ReadOnly]
    mode = PropGoldenChoice.Automatic

    #[Category("Text"), Name("Caption"), HelpBox("Changes apply to the next shapes drawn too.")]
    caption: String
}

impl Gui.IPropertyNotify for PropGoldenData
{
    mtd impl validateItem(_: *Gui.Properties, item: *Gui.PropertiesItem)->Gui.PropValidationResult
    {
        if item.typeValue.crc == Reflection.fieldCrc(PropGoldenData, #nameof(PropGoldenData.caption)) and .caption.length > 40 do
            return {.Warning, "Over 40 characters: the caption will be cut."}
        return {}
    }
}

// The settings of a drawn shape, in sections and subsections, for the property editor at its
// fullest: the section list, the search, and the presentation menu.
struct PropCtrlGoldenData
{
    #[Category("Appearance"), Name("Opacity"), SliderMinMax(0, 1)]
    opacity: f32 = 1

    #[Category("Appearance"), Name("Outline Opacity"), SliderMinMax(0, 1)]
    outlineOpacity: f32 = 1

    #[Category("Layout"), Name("Width")]
    width: f32 = 320

    #[Category("Layout"), Name("Height")]
    height: f32 = 200

    #[Category("Text"), Name("Font Size")]
    fontSize: f32 = 14

    #[Category("Advanced/Rendering"), Name("Optimize Gradients")]
    optimizeGradients = true

    #[Category("Advanced/Export"), Name("Scale")]
    scale: f32 = 2
}
