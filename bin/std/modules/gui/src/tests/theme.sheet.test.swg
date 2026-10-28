#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A sheet that names palette tokens re-derives the whole interface, not only the tokens it
// named. This is what makes a user theme a page of text instead of three hundred lines, and
// it is the property a delta-based theme cannot have.
#test
{
    var theme: Theme
    theme.setDark()

    let sheet = """
                /ThemePalette
                ground              0xFF102030
                signature.mark      0xFF00A0FF
                signature.ground    0xFF00A0FF
                signature.onGround  0xFF000000
                """

    expect theme.applySheet(sheet)

    Swag.assert(theme.palette.signature.mark == 0xFF00A0FF)
    Swag.assert(theme.colors.signature == 0xFF00A0FF)
    Swag.assert(theme.colors.focusRing == 0xFF00A0FF)
    Swag.assert(theme.colors.caret == 0xFF00A0FF)
    Swag.assert(theme.colors.btnPush_StrongBk == 0xFF00A0FF)
    Swag.assert(theme.colors.btnPushDefault_Bk == 0xFF00A0FF)
    Swag.assert(theme.colors.btnPush_StrongText == 0xFF000000)
    Swag.assert(theme.colors.wnd_Bk == 0xFF102030)
    Swag.assert(theme.colors.informationBar_Bk == 0xFF102030)

    // Everything the signature does not decide is left exactly where the palette had it.
    Swag.assert(theme.colors.surface == 0xFF1F2026)
    Swag.assert(theme.colors.text == 0xFFECEDF0)
}

// A name reaching into a tone with '.' is what makes a tone writable at all. Before it, a folder
// field that was itself a struct could be named but never assigned, which left the whole
// image-rect folder registered and unreachable.
#test
{
    var theme: Theme
    theme.setDark()

    let sheet = """
                /ThemeImageRects
                btnPush_Normal.radius   3
                /ThemePalette
                alternate.ground        0xFF7F00FF
                """

    expect theme.applySheet(sheet)

    Swag.assert(theme.rects.btnPush_Normal.radius == 3)
    Swag.assert(theme.palette.alternate.ground == 0xFF7F00FF)
    Swag.assert(theme.colors.btnCheck_CheckedBk == 0xFF7F00FF)
    Swag.assert(theme.colors.btnToggle_OnBk == 0xFF7F00FF)

    // The rest of the rect is untouched: a path names one value, not the struct around it.
    Swag.assert(theme.rects.btnPush_Normal.rect == theme.rects.edit_SquareBk.rect)
}

// A tone is two decisions, and a sheet may take them apart: what the theme points with and
// what it fills with are separate values precisely so a palette can keep a brand color for the
// blocks and a legible one for the hairlines.
#test
{
    var theme: Theme
    theme.setDark()

    let sheet = """
                /ThemePalette
                signature.mark      0xFF00A0FF
                signature.ground    0xFFFF8000
                """

    expect theme.applySheet(sheet)

    // The rings and the caret point with the mark; the primary action fills with the block, and
    // its own edge is the block too.
    Swag.assert(theme.colors.focusRing == 0xFF00A0FF)
    Swag.assert(theme.colors.edit_FocusBorder == 0xFF00A0FF)
    Swag.assert(theme.colors.caret == 0xFF00A0FF)

    Swag.assert(theme.colors.btnPush_StrongBk == 0xFFFF8000)
    Swag.assert(theme.colors.btnPushDefault_Bk == 0xFFFF8000)
    Swag.assert(theme.colors.btnPush_StrongBorder == 0xFFFF8000)
}

// A '$' reference resolves through a path too, and the two sides still have to agree on a type.
#test
{
    var theme: Theme
    theme.setDark()

    let sheet = """
                /ThemePalette
                alternate.mark      $signature.mark
                """

    expect theme.applySheet(sheet)
    Swag.assert(theme.colors.arc == theme.colors.focusRing)

    var errOutcome: Swag.Error
    catch theme.applySheet("/ThemePalette\nalternate.mark $critical") as errOutcome
    let err = errOutcome.value()
    Swag.assert(err != null)
}

// The two folders of a sheet are two layers: the tokens derive the interface, then the named
// parts override what the derivation produced. Order in the file must not matter, which is
// why the text is read twice.
#test
{
    var theme: Theme
    theme.setDark()

    let sheet = """
                /ThemeColors
                btnPush_Bk  0xFF123456
                /ThemePalette
                raised      0xFFAABBCC
                """

    expect theme.applySheet(sheet)

    Swag.assert(theme.palette.raised == 0xFFAABBCC)
    Swag.assert(theme.colors.btnPush_HotBk == 0xFFAABBCC)
    Swag.assert(theme.colors.btnPush_Bk == 0xFF123456)
}

// A sheet naming no token at all stays a plain delta over the colors already applied.
#test
{
    var theme: Theme
    theme.setLight()

    expect theme.applySheet("/ThemeColors\nlabel_Text 0xFF804020")

    Swag.assert(theme.colors.label_Text == 0xFF804020)
    Swag.assert(theme.colors.text == 0xFF1A1B1E)
    Swag.assert(theme.palette.text == 0xFF1A1B1E)
}

// A malformed sheet is reported with the line it failed on rather than silently ignored: a
// theme file is written by hand, so the failure has to be readable. A path that walks into a
// tone and misses is the same kind of mistake as a token that does not exist.
#test
{
    var theme: Theme
    theme.setDark()

    var errOutcome: Swag.Error
    catch theme.applySheet("/ThemePalette\nsignature.mark 0xFF000000\nnotAToken 3") as errOutcome
    let err = errOutcome.value()
    Swag.assert(err != null)

    var pathErrOutcome: Swag.Error
    catch theme.applySheet("/ThemePalette\nsignature.notAPart 0xFF000000") as pathErrOutcome
    let pathErr = pathErrOutcome.value()
    Swag.assert(pathErr != null)
}
