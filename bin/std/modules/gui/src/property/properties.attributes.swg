#global public

using Core, Pixel

// Turns a string declared by a property attribute into the text the grid shows.
//
// The argument is the literal the attribute carries — `#[Properties.Name("Thickness")]`
// passes `"Thickness"` — and the result is what the reader sees. An attribute value is a
// compile-time constant, so this is what lets a declared wording act as a translation key.
// Answer `null` for a string the resolver does not own: the module that declared it answers
// next, and the declared wording is what remains when nobody does.
alias PropertyTextResolver = func(string)->#null string

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

    // String edition that takes a file dragged from the desktop, whose path replaces the value.
    //
    // Marks a field that names a document rather than holding free text: dropping one file on
    // its editor fills it, which is the gesture a reader reaches for before a browse dialog.
    // The value commits the way a typed one does, when the editor loses the focus.
    attr FilePath()

    // Restricts color editing to opaque colors.
    attr Opaque()

    // Preserves the field's alpha channel while editing its color.
    attr KeepAlpha()

    // Mark a field read-only: it is shown but its editor is grayed and non-editable, and the
    // "Paste" context-menu action is disabled. See also IPropertyNotify.isItemReadOnly for a
    // dynamic (runtime) equivalent.
    attr ReadOnly()
}

// The resolver every generated label passes through; `null` shows the declared strings.
private var g_TextResolver: #null PropertyTextResolver

impl Properties
{
    // Installs the resolver every string a property attribute declares passes through.
    //
    // Every label, description, category segment, heading, note, unit, and enumeration entry
    // the grid generates from reflection is resolved through `resolver`, so an application
    // that translates its interface makes `#[Properties.Name("Thickness")]` a key rather than
    // a final wording. One resolver serves every grid in the process, and the strings this
    // module declares itself are resolved after it, so an application only answers for its
    // own. Pass `null` to show the declared strings again.
    //
    // Install it before building a grid — a row already built keeps the text it was created
    // with — and rebuild the grids that must follow a language switch. GUI thread only.
    //
    // ```swag
    // Properties.setTextResolver(func(key: string)->#null string
    // {
    //     switch key
    //     {
    //     case "Thickness": return appStrings().prop_Thickness
    //     }
    //     return null
    // })
    // ```
    func setTextResolver(resolver: #null PropertyTextResolver)
    {
        g_TextResolver = resolver
    }

    // Returns the text to show for a string declared by a property attribute.
    //
    // Consults the installed resolver first, then the strings this module declares itself,
    // and answers `text` unchanged when neither owns it. Custom editors registered through
    // [[Gui.Properties.registerEditor]] call this so their labels follow the same resolution
    // as the built-in ones.
    func resolveText(text: string)->string
    {
        let resolver = g_TextResolver
        if resolver
        {
            if let resolved = resolver(text) do
                return resolved
        }

        return moduleText(text)
    }

    // Wording of the property strings this module declares, in the active language.
    //
    // [[Gui.ApplicationOptions]] is the only struct the module reflects into a grid, so this
    // is the whole set. It answers after the installed resolver, which lets an application
    // override a diagnostic label without having to know the rest.
    private func moduleText(text: string)->string
    {
        let s = strings()
        switch text
        {
        case "Debug":                                                        return s.prop_CategoryDebug
        case "Show Clip Rect":                                               return s.prop_ShowClipRect
        case "Display an overlay of the current drawing clipping rectangle": return s.prop_ShowClipRectDesc
        case "Show Layout Rects":                                            return s.prop_ShowLayoutRects
        case "Display layout rectangles computed by layout controls":        return s.prop_ShowLayoutRectsDesc
        case "Dump Layout Tree":                                             return s.prop_DumpLayoutTree
        case "Enable layout tree dumps from debug tooling":                  return s.prop_DumpLayoutTreeDesc
        }

        return text
    }
}
