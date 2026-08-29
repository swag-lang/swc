#global private

using Swag, Core

// A sheet that names palette tokens re-derives the whole interface, not only the tokens it
// named. This is what makes a user theme a page of text instead of three hundred lines, and
// it is the property a delta-based theme cannot have.
#test
{
    var theme: Theme
    theme.setSwagDark()

    let sheet = """
                /ThemePalette
                informationBar      0xFF102030
                signature.mark      0xFF00A0FF
                signature.ground    0xFF00A0FF
                signature.onGround  0xFF000000
                """

    expect theme.applySheet(sheet)

    @assert(theme.palette.signature.mark == 0xFF00A0FF)
    @assert(theme.colors.hilight == 0xFF00A0FF)
    @assert(theme.colors.focusRing == 0xFF00A0FF)
    @assert(theme.colors.activeRail == 0xFF00A0FF)
    @assert(theme.colors.btnPush_StrongBk == 0xFF00A0FF)
    @assert(theme.colors.btnPushDefault_Bk == 0xFF00A0FF)
    @assert(theme.colors.slider_Mark == 0xFF00A0FF)
    @assert(theme.colors.progressBar_Mark == 0xFF00A0FF)
    @assert(theme.colors.btnPush_StrongText == 0xFF000000)
    @assert(theme.colors.informationBar_Bk == 0xFF102030)

    // Everything the signature does not decide is left exactly where the palette had it.
    @assert(theme.colors.bk == 0xFF0B0B0D)
    @assert(theme.colors.text == 0xFFE9E9ED)
}

// A name reaching into a tone with '.' is what makes a tone writable at all. Before it, a folder
// field that was itself a struct could be named but never assigned, which left the whole
// image-rect folder registered and unreachable.
#test
{
    var theme: Theme
    theme.setSwagDark()

    let sheet = """
                /ThemeImageRects
                btnPush_Normal.radius   3
                /ThemePalette
                alternate.ground        0xFF7F00FF
                """

    expect theme.applySheet(sheet)

    @assert(theme.rects.btnPush_Normal.radius == 3)
    @assert(theme.palette.alternate.ground == 0xFF7F00FF)
    @assert(theme.colors.btnPush_AlternateBk == 0xFF7F00FF)

    // The rest of the rect is untouched: a path names one value, not the struct around it.
    @assert(theme.rects.btnPush_Normal.rect == theme.rects.edit_SquareBk.rect)
}

// A tone is two decisions, and a sheet may take them apart: what the theme points with and
// what it fills with are separate values precisely so a palette can keep a brand color for the
// blocks and a legible one for the hairlines.
#test
{
    var theme: Theme
    theme.setSwagDark()

    let sheet = """
                /ThemePalette
                signature.mark      0xFF00A0FF
                signature.ground    0xFFFF8000
                """

    expect theme.applySheet(sheet)

    @assert(theme.colors.activeRail == 0xFF00A0FF)
    @assert(theme.colors.focusRing == 0xFF00A0FF)
    @assert(theme.colors.edit_FocusBorder == 0xFF00A0FF)
    @assert(theme.colors.slider_Mark == 0xFF00A0FF)

    @assert(theme.colors.btnPush_StrongBk == 0xFFFF8000)
    @assert(theme.colors.btnPushDefault_Bk == 0xFFFF8000)
    @assert(theme.colors.btnToggle_OnBk == 0xFFFF8000)
    @assert(theme.colors.slider_HilightBk == 0xFFFF8000)
    @assert(theme.colors.progressBar_Mark == 0xFFFF8000)

    // The outline of a filled action comes from the mark, which is what gives the block an edge
    // when its own color is too close to the ground behind it.
    @assert(theme.colors.btnPush_StrongBorder == 0xFF00A0FF)
}

// A '$' reference resolves through a path too, and the two sides still have to agree on a type.
#test
{
    var theme: Theme
    theme.setSwagDark()

    let sheet = """
                /ThemePalette
                alternate.mark      $signature.mark
                """

    expect theme.applySheet(sheet)
    @assert(theme.colors.url_Text == theme.colors.hilight)

    catch theme.applySheet("/ThemePalette\nalternate.mark $railed") as err
    @assert(err != null)
}

// The two folders of a sheet are two layers: the tokens derive the interface, then the named
// parts override what the derivation produced. Order in the file must not matter, which is
// why the text is read twice.
#test
{
    var theme: Theme
    theme.setSwagDark()

    let sheet = """
                /ThemeColors
                btnPush_Bk  0xFF123456
                /ThemePalette
                raised      0xFFAABBCC
                """

    expect theme.applySheet(sheet)

    @assert(theme.palette.raised == 0xFFAABBCC)
    @assert(theme.colors.edit_Bk == 0xFFAABBCC)
    @assert(theme.colors.btnPush_Bk == 0xFF123456)
}

// A sheet naming no token at all stays a plain delta over the colors already applied.
#test
{
    var theme: Theme
    theme.setLight()

    expect theme.applySheet("/ThemeColors\nlabel_Text 0xFF804020")

    @assert(theme.colors.label_Text == 0xFF804020)
    @assert(theme.colors.text == 0xFF1F1F1F)
    @assert(theme.palette.text == 0xFF1F1F1F)
}

// A malformed sheet is reported with the line it failed on rather than silently ignored: a
// theme file is written by hand, so the failure has to be readable. A path that walks into a
// tone and misses is the same kind of mistake as a token that does not exist.
#test
{
    var theme: Theme
    theme.setDark()

    catch theme.applySheet("/ThemePalette\nsignature.mark 0xFF000000\nnotAToken 3") as err
    @assert(err != null)

    catch theme.applySheet("/ThemePalette\nsignature.notAPart 0xFF000000") as pathErr
    @assert(pathErr != null)
}
