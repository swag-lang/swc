#global if #command == Swag.CompilerCommand.Test

using Swag, Core, Pixel

// A private table with its own language file, as an application would register one.
struct TestStrings
{
    hello:  string = "Hello"
    stay:   string = "Stay"
    quoted: string = "Plain"
}

var g_TestStrings: TestStrings

const TestFrench = "# comment\nhello Bonjour\nquoted \"  Salut\"\n"

// The reference wording is the declared one, and 'en' is always active at start.
#test
{
    @assert(strings().dlg_Ok == "OK")
    @assert(strings().dlg_Cancel == "Cancel")
    @assert(activeLanguage() == "en")
}

// A language switch retargets every registered table, keeps omitted keys, decodes
// quoted values, and 'en' restores the reference strings.
#test
{
    var res: Resources.Bundle
    registerDefaultStrings(&res)
    registerStrings'TestStrings(&g_TestStrings, "testtable")
    res.addEmbedded("lang/fr/testtable.tweak", cast(const [..] u8) TestFrench)

    // Whatever this test asserts, the next test starts from the reference language.
    defer discard catch applyLanguage(&res, "en")

    expect applyLanguage(&res, "fr")
    @assert(activeLanguage() == "fr")
    @assert(g_TestStrings.hello == "Bonjour")
    @assert(g_TestStrings.stay == "Stay")
    @assert(g_TestStrings.quoted == "  Salut")

    // The GUI table follows the same switch through its embedded translation.
    @assert(strings().dlg_Cancel == "Annuler")
    @assert(strings().dlg_ConfirmTitle == "Veuillez confirmer")

    expect applyLanguage(&res, "en")
    @assert(activeLanguage() == "en")
    @assert(g_TestStrings.hello == "Hello")
    @assert(strings().dlg_Cancel == "Cancel")
}

// An unregistered tag fails without touching the tables.
#test
{
    var res: Resources.Bundle
    registerDefaultStrings(&res)

    discard catch applyLanguage(&res, "xx") as err
    @assert(err != null)
    @assert(err is Core.Errors.BadParameterError)
    @assert(activeLanguage() == "en")
    @assert(strings().dlg_Ok == "OK")
}

// A registered tag with no language file for any table fails the same way.
#test
{
    var res: Resources.Bundle
    registerDefaultStrings(&res)
    registerLanguage("xx", "Xhosa")

    discard catch applyLanguage(&res, "xx") as err
    @assert(err != null)
    @assert(err is Core.Errors.FileNotFoundError)
    @assert(activeLanguage() == "en")
    @assert(strings().dlg_Ok == "OK")
}

// The reference language always comes first, and the module registers what it ships.
#test
{
    var res: Resources.Bundle
    registerDefaultStrings(&res)

    let all = languages()
    @assert(@countof(all) >= 2)
    @assert(all[0].tag == ReferenceLanguage)
    @assert(all[0].builtin)
    @assert(all[0].nativeName == "English")

    let french = findLanguage("fr")
    @assert(french != null)
    @assert(french.nativeName == "Français")
    @assert(!french.builtin)
    @assert(findLanguage("zz") == null)

    // The account language decides, and an unshipped one falls back to the reference.
    @assert(findLanguage(systemLanguage()) != null)
}

// Validation rejects an unknown key and a malformed line, with the faulty line number.
#test
{
    expect validateStrings'TestStrings("hello Bonjour\n")

    discard catch validateStrings'TestStrings("helo Bonjour\n") as err
    @assert(err != null)
    @assert(err is Core.Errors.SyntaxError)
    @assert((cast(const *Core.Errors.SyntaxError) err).line == 1)

    discard catch validateStrings'TestStrings("hello ok\n1bad value\n") as err2
    @assert(err2 != null)
    @assert((cast(const *Core.Errors.SyntaxError) err2).line == 2)
}

// A theme sheet drives colors, metrics, and atlas rects, with '$' references.
#test
{
    var theme: Theme
    let sheet = "/ThemeColors\nbtnPush_Bk 0xFF102030\n/ThemeMetrics\nbtnPush_Height 44\n/ThemeImageRects\nbtnPush_Normal {{1 29 27 27} 5}\nbtnPush_Hot $btnPush_Normal\n"
    expect theme.applySheet(sheet)

    @assert(theme.colors.btnPush_Bk.argb == 0xFF102030)
    @assert(theme.metrics.btnPush_Height == 44)
    @assert(theme.rects.btnPush_Normal.rect.y == 29)
    @assert(theme.rects.btnPush_Normal.corner == 5)
    @assert(theme.rects.btnPush_Hot.rect.x == 1)
    @assert(theme.rects.btnPush_Hot.corner == 5)

    // An unknown key is a sheet error carrying its line.
    discard catch theme.applySheet("/ThemeColors\nnotAColor 0xFF000000\n") as err
    @assert(err != null)
    @assert(err is Core.Errors.SyntaxError)
}

// A sheet resource resolves through a bundle, embedded content included.
#test
{
    const CustomSheet = "/ThemeMetrics\nbtnPush_Width 123\n"

    var res: Resources.Bundle
    res.addEmbedded("themes/custom.tweak", cast(const [..] u8) CustomSheet)

    var theme: Theme
    expect theme.loadSheet(&res, "themes/custom.tweak")
    @assert(theme.metrics.btnPush_Width == 123)

    discard catch theme.loadSheet(&res, "themes/missing.tweak") as err
    @assert(err != null)
    @assert(err is Core.Errors.FileNotFoundError)
}
