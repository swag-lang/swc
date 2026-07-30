#global public

using Core, Pixel

// Represents theme style ref.
struct ThemeStyleRef
{
    #[Swag.Late]
    theme: *Theme     // Theme associated with this value.
    count: u32        // Count associated with this value.
}

// Represents theme style.
struct ThemeStyle
{
    styleSheetMetrics: String         // Style sheet metrics associated with this value.
    styleSheetColors:  String         // Style sheet colors associated with this value.
    font:              FontFamily     // Font associated with this value.

    // The shared theme this style resolves against, and whether it must be resolved again.
    // The style takes and releases the reference itself, so its count stays correct.
    internal
    {
        refr:  #null *ThemeStyleRef     // Reference-counted theme this style resolves to.
        dirty: bool                     // Whether the style sheets must be applied again.
    }
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
        if !.refr do
            return

        let refr = notnull .refr
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
        let refr = notnull other.refr
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

    // Create a specific style based on the parent
    mtd create(parent: *ThemeStyle)
    {
        .free()
        var theme = Memory.new'Theme()
        dref theme = dref (notnull parent.refr).theme
        .set(theme)
    }

    private mtd compute(owner: *Wnd, parent: *ThemeStyle)
    {
        // First time, initialize to parent
        if !.refr
        {
            .share(parent)
            .dirty = true
        }

        // If parent is dirty, or i am dirty, then we need
        // to compute.
        if !.dirty and !parent.dirty do
            return
        .dirty = true

        // By default, same as the parent
        .share(parent)

        // Ask user
        var evt = ThemeEvent{}
        evt.accepted = false
        evt.style    = me
        evt.parent   = parent
        owner.sendEvent(&evt)

        // Nothing to override
        if .styleSheetColors.length == 0 and
           .styleSheetMetrics.length == 0 and
           !.font.regular and
           !.font.bold and
           !.font.italic and
           !.font.boldItalic and
           !evt.accepted
        {
            return
        }

        // Make a new tweak as a copy of the parent
        if .refr == parent.refr do
            .create(parent)

        // Then tweak it with the stylesheet
        let own = notnull .refr
        if .styleSheetColors.length
        {
            var tf: File.TweakFile
            tf.registerFolder'ThemeColors(&own.theme.colors)
            catch tf.parse(.styleSheetColors)
        }

        if .styleSheetMetrics.length
        {
            var tf: File.TweakFile
            tf.registerFolder'ThemeMetrics(&own.theme.metrics)
            catch tf.parse(.styleSheetMetrics)
        }
    }

    // Performs the clear style sheet colors operation.
    mtd clearStyleSheetColors()
    {
        .styleSheetColors.clear()
        .dirty = true
    }

    // Sets style sheet colors.
    mtd setStyleSheetColors(str: string)
    {
        .styleSheetColors = str
        .dirty            = true
    }

    // Adds style sheet colors.
    mtd addStyleSheetColors(str: string)
    {
        .styleSheetColors.append("\n")
        .styleSheetColors.append(str)
        .dirty = true
    }

    // Sets style sheet metrics.
    mtd setStyleSheetMetrics(str: string)
    {
        .styleSheetMetrics = str
        .dirty             = true
    }

    // Adds style sheet metrics.
    mtd addStyleSheetMetrics(str: string)
    {
        .styleSheetMetrics.append("\n")
        .styleSheetMetrics.append(str)
        .dirty = true
    }

    // Returns font.
    mtd const getFont()->FontFamily
    {
        var result: retval
        let df = &(notnull .refr).theme.res.fontDefault
        result.regular    = .font.regular orelse df.regular
        result.bold       = .font.bold orelse df.bold
        result.italic     = .font.italic orelse df.italic
        result.boldItalic = .font.boldItalic orelse df.boldItalic
        return result
    }

    // Sets font.
    mtd setFont(fnt: FontFamily)
    {
        .font  = fnt
        .dirty = true
    }

    // Sets font.
    mtd setFont(fnt: *Font, style: FontFamilyStyle)
    {
        .font.setFont(fnt, style)
        .dirty = true
    }

    // Performs the clear font operation.
    mtd clearFont()
    {
        @init(&.font, 1)
        .dirty = true
    }
}
