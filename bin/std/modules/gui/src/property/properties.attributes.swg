#global public
using Core, Pixel

impl Properties
{
    // Start a new category. A "/"-separated name opens nested subgroups: Category("Transform/Advanced")
    // creates a "Transform" group with an "Advanced" subgroup indented under it. Consecutive fields
    // sharing a common prefix reuse the same headers.
    attr Category(name: string)

    // Decorator: insert a bold, non-collapsible divider label above the field.
    // Named 'Heading' to avoid clashing with the existing Header widget type.
    attr Heading(text: string)

    // Decorator: insert an empty vertical gap ('size' px) above the field.
    // Named 'Gap' to avoid clashing with the Key.Space enum used inside impl Properties.
    attr Gap(size: s32)

    // Decorator: insert an informational note bar above the field.
    attr HelpBox(text: string)

    // Change the field display name
    attr Name(name: string)

    // Add a description
    attr Description(desc: string)

    // The width of the edition widget
    attr EditSize(size: s32)

    // If the value changed, need to recompute the properties layout
    attr RecalcLayout()

    // Value edition with an editbox, min and max values
    attr MinMax(min, max: s64)

    // Value edition with an editbox, show a unit string
    attr Unit(value: string)

    // Float edition, edit width a slider instead of an editbox
    attr SliderMinMax(min, max: f32)

    // Color edition, force an opaque color
    attr Opaque()

    // Color edition, keep the original alpha value
    attr KeepAlpha()

    // Mark a field read-only: it is shown but its editor is grayed and non-editable, and the
    // "Paste" context-menu action is disabled. See also IPropertyNotify.isItemReadOnly for a
    // dynamic (runtime) equivalent.
    attr ReadOnly()
}
