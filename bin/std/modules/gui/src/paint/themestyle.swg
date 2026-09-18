#global public

using Core, Pixel

// Shares one owned theme between copied window styles.
struct ThemeStyleRef
{
    public
    {
        late theme: *Theme     // Shared theme, released with the last style holding it.
        count:      u32        // Number of styles holding the reference.
    }
}

// Applies local font, color, and metric overrides on top of a shared theme.
struct ThemeStyle
{
    public
    {
        styleSheetMetrics: String     // Local metric overrides, one `name value` line per [[Gui.ThemeMetrics]] field.
        styleSheetColors:  String     // Local color overrides, one `name value` line per [[Gui.ThemeColors]] field.
        font: FontFamily              // Local font faces; a `null` face inherits the theme default.
    }

    // The shared theme this style resolves against, and whether it must be resolved again.
    // The style takes and releases the reference itself, so its count stays correct.
    refr:  *ThemeStyleRef?     // Reference-counted theme this style resolves to.
    dirty: bool                // Whether the style sheets must be applied again.
}

impl ThemeStyle
{
    // Releases resources owned by this value.
    mtd opDrop()
    {
        .free()
    }

    // Drops this style's reference on its theme, and the theme with it when it was the last one.
    //
    // Clearing 'refr' whatever the resulting count is what makes this idempotent: a style that has
    // released its reference no longer holds a pointer it could decrement a second time.
    private mtd free()
    {
        if not .refr do
            return

        let refr = .refr
        .refr      = null
        refr.count -= 1
        if refr.count == 0
        {
            Memory.delete(refr.theme)
            Memory.delete(refr)
        }
    }

    // Takes ownership of a theme, as the sole holder for now.
    mtd own(theme: *Theme)
    {
        .free()
        .refr       = Memory.new'ThemeStyleRef()
        .refr.theme = theme
        .refr.count = 1
    }

    // Takes a reference on the theme another style already holds.
    //
    // Use this rather than copying `refr` by hand: the reference count then follows the number of
    // holders instead of having to be set to match it.
    mtd share(other: *ThemeStyle)
    {
        let refr = other.refr!
        if .refr == refr do
            return

        .free()
        .refr      = refr
        refr.count += 1
    }

    private mtd set(theme: *Theme)
    {
        .own(theme)
    }

    // Creates a private theme copy from a parent style.
    mtd create(parent: *ThemeStyle)
    {
        .free()
        let theme = Memory.new'Theme()
        theme[] = parent.refr!.theme[]
        .set(theme)
    }

    private mtd compute(owner: *Wnd, parent: *ThemeStyle)
    {
        // First time, initialize to parent
        if not .refr
        {
            .share(parent)
            .dirty = true
        }

        // Nothing to resolve unless this style or its parent changed.
        if not .dirty and not parent.dirty do
            return
        .dirty = true

        // By default, same as the parent
        .share(parent)

        // Let the owner customize the style.
        var evt = ThemeEvent{}
        evt.accepted = false
        evt.style    = me
        evt.parent   = parent
        owner.sendEvent(&evt)

        // Nothing to override
        if .styleSheetColors.isEmpty() and
           .styleSheetMetrics.isEmpty() and
           not .font.regular and
           not .font.bold and
           not .font.italic and
           not .font.boldItalic and
           not evt.accepted
        {
            return
        }

        // Make a new tweak as a copy of the parent
        if .refr == parent.refr do
            .create(parent)

        // Then tweak it with the stylesheet
        let own = .refr!
        if not .styleSheetColors.isEmpty()
        {
            var tf: File.TweakFile
            tf.registerFolder'ThemeColors(&own.theme.colors)
            catch tf.parse(.styleSheetColors)
        }

        if not .styleSheetMetrics.isEmpty()
        {
            var tf: File.TweakFile
            tf.registerFolder'ThemeMetrics(&own.theme.metrics)
            catch tf.parse(.styleSheetMetrics)
        }
    }

    // Removes every local color override.
    mtd clearStyleSheetColors()
    {
        .styleSheetColors.clear()
        .dirty = true
    }

    // Replaces the local color overrides with the `name value` lines of `str`.
    mtd setStyleSheetColors(str: string)
    {
        .styleSheetColors = str
        .dirty = true
    }

    // Appends the `name value` lines of `str` to the local color overrides.
    mtd addStyleSheetColors(str: string)
    {
        .styleSheetColors.append("\n")
        .styleSheetColors.append(str)
        .dirty = true
    }

    // Replaces the local metric overrides with the `name value` lines of `str`.
    mtd setStyleSheetMetrics(str: string)
    {
        .styleSheetMetrics = str
        .dirty = true
    }

    // Appends the `name value` lines of `str` to the local metric overrides.
    mtd addStyleSheetMetrics(str: string)
    {
        .styleSheetMetrics.append("\n")
        .styleSheetMetrics.append(str)
        .dirty = true
    }

    // Returns the local font slots with missing faces inherited from the theme default.
    mtd const resolvedFont()->FontFamily
    {
        var result: retval
        let df = &.refr!.theme.res.fontDefault
        result.regular    = .font.regular orelse df.regular
        result.bold       = .font.bold orelse df.bold
        result.italic     = .font.italic orelse df.italic
        result.boldItalic = .font.boldItalic orelse df.boldItalic
        return result
    }

    // Replaces every local font face with those of `fnt`.
    mtd setFont(fnt: FontFamily)
    {
        .font  = fnt
        .dirty = true
    }

    // Replaces the local `style` face with `fnt`.
    mtd setFont(fnt: *Font, style: FontFamilyStyle)
    {
        .font.setFont(fnt, style)
        .dirty = true
    }

    // Removes every local font-face override.
    mtd clearFont()
    {
        Swag.init(&.font, 1)
        .dirty = true
    }
}
