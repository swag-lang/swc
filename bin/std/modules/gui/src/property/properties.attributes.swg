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

    // Replaces the reflected field name with a presentation label.
    attr Name(name: string)

    // Adds explanatory text below the field label.
    attr Description(desc: string)

    // Sets the preferred width of the field editor.
    attr EditSize(size: s32)

    // Recomputes the property layout after this field changes.
    attr RecalcLayout()

    // Constrains numeric editing to an inclusive minimum and maximum.
    attr MinMax(min, max: s64)

    // Displays a unit suffix beside the field editor.
    attr Unit(value: string)

    // Edits a floating-point value with a slider over the supplied range.
    attr SliderMinMax(min, max: f32)

    // Bool edition with a two-entries combo box instead of a check box; 'off' is the
    // label of the false value, 'on' the label of the true one ("No Shadow"/"Small").
    attr BoolCombo(off, on: string)

    // String edition with an extra '...' button opening a multi-line edition dialog.
    attr MultiLine()

    // String edition with a combo box of the system font families; the first entry is
    // the theme's default font and stores an empty string.
    attr FontName()

    // Restricts color editing to opaque colors.
    attr Opaque()

    // Preserves the field's alpha channel while editing its color.
    attr KeepAlpha()

    // Mark a field read-only: it is shown but its editor is grayed and non-editable, and the
    // "Paste" context-menu action is disabled. See also IPropertyNotify.isItemReadOnly for a
    // dynamic (runtime) equivalent.
    attr ReadOnly()
}
