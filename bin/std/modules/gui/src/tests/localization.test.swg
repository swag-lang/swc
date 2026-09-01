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

// A second table, registered only once a language is already active, the way a plugin library
// loaded on demand registers its own.
struct LateStrings
{
    hello: string = "Hello"
}

var g_LateStrings: LateStrings

const TestFrench = "# comment\nhello Bonjour\nquoted \"  Salut\"\n"

// An application-wide notification visits each window exactly once. It is a broadcast over the
// tree, not a routed child event that parents should receive again for every descendant.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 180)
    defer host.shutdown()

    let child = Wnd.create'Wnd(&host.root)
    var rootNotifications, childNotifications: u32
    host.root.hookOnEvent = func|count = &rootNotifications|(wnd, evt)
    {
        discard wnd
        switch evt
        {
        case NotifyEvent as notify where notify.kind == .LanguageChanged:
            count[] += 1
        }

        return false
    }

    child.hookOnEvent = func|count = &childNotifications|(wnd, evt)
    {
        discard wnd
        switch evt
        {
        case NotifyEvent as notify where notify.kind == .LanguageChanged:
            count[] += 1
        }

        return false
    }

    host.notify(.LanguageChanged)
    Swag.assert(rootNotifications == 1)
    Swag.assert(childNotifications == 1)
}

// The reference wording is the declared one, and 'en' is always active at start.
#test
{
    Swag.assert(strings().dlg_Ok == "OK")
    Swag.assert(strings().dlg_Cancel == "Cancel")
    Swag.assert(activeLanguage() == "en")
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
    Swag.assert(activeLanguage() == "fr")
    Swag.assert(g_TestStrings.hello == "Bonjour")
    Swag.assert(g_TestStrings.stay == "Stay")
    Swag.assert(g_TestStrings.quoted == "  Salut")

    // The GUI table follows the same switch through its embedded translation.
    Swag.assert(strings().dlg_Cancel == "Annuler")
    Swag.assert(strings().dlg_ConfirmTitle == "Veuillez confirmer")

    expect applyLanguage(&res, "en")
    Swag.assert(activeLanguage() == "en")
    Swag.assert(g_TestStrings.hello == "Hello")
    Swag.assert(strings().dlg_Cancel == "Cancel")
}

// A table registered after the switch takes the active language on the spot. This is the whole
// reason a viewer plugin loaded on demand opens in the language of the window around it instead
// of in English until the next switch.
#test
{
    var res: Resources.Bundle
    registerDefaultStrings(&res)
    res.addEmbedded("lang/fr/latetable.tweak", cast(const [..] u8) TestFrench)
    defer discard catch applyLanguage(&res, "en")

    expect applyLanguage(&res, "fr")
    Swag.assert(g_LateStrings.hello == "Hello")

    registerStrings'LateStrings(&g_LateStrings, "latetable")
    Swag.assert(g_LateStrings.hello == "Bonjour")

    // And it follows every later switch like any other table.
    expect applyLanguage(&res, "en")
    Swag.assert(g_LateStrings.hello == "Hello")
}

// An unregistered tag fails without touching the tables.
#test
{
    var res: Resources.Bundle
    registerDefaultStrings(&res)

    discard catch applyLanguage(&res, "xx") as err
    Swag.assert(err != null)
    Swag.assert(err is Core.Errors.BadParameterError)
    Swag.assert(activeLanguage() == "en")
    Swag.assert(strings().dlg_Ok == "OK")
}

// A registered tag with no language file for any table fails the same way.
#test
{
    var res: Resources.Bundle
    registerDefaultStrings(&res)
    registerLanguage("xx", "Xhosa")

    discard catch applyLanguage(&res, "xx") as err
    Swag.assert(err != null)
    Swag.assert(err is Core.Errors.FileNotFoundError)
    Swag.assert(activeLanguage() == "en")
    Swag.assert(strings().dlg_Ok == "OK")
}

// The reference language always comes first, and the module registers what it ships.
#test
{
    var res: Resources.Bundle
    registerDefaultStrings(&res)

    let all = languages()
    Swag.assert(all.count >= 2)
    Swag.assert(all[0].tag == ReferenceLanguage)
    Swag.assert(all[0].builtin)
    Swag.assert(all[0].nativeName == "English")

    let french = findLanguage("fr")
    Swag.assert(french != null)
    Swag.assert(french.nativeName == "Français")
    Swag.assert(!french.builtin)
    Swag.assert(findLanguage("zz") == null)

    // The account language decides, and an unshipped one falls back to the reference.
    Swag.assert(findLanguage(systemLanguage()) != null)
}

// Validation rejects an unknown key and a malformed line, with the faulty line number.
#test
{
    expect validateStrings'TestStrings("hello Bonjour\n")

    discard catch validateStrings'TestStrings("helo Bonjour\n") as err
    Swag.assert(err != null)
    Swag.assert(err is Core.Errors.SyntaxError)
    Swag.assert((cast(const *Core.Errors.SyntaxError) err).line == 1)

    discard catch validateStrings'TestStrings("hello ok\n1bad value\n") as err2
    Swag.assert(err2 != null)
    Swag.assert((cast(const *Core.Errors.SyntaxError) err2).line == 2)
}

// A theme sheet drives colors, metrics, and atlas rects, with '$' references.
#test
{
    var theme: Theme
    let sheet = "/ThemeColors\nbtnPush_Bk 0xFF102030\n/ThemeMetrics\nbtnPush_Height 44\n/ThemeImageRects\nbtnPush_Normal {{1 29 27 27} 5}\nbtnPush_Hot $btnPush_Normal\n"
    expect theme.applySheet(sheet)

    Swag.assert(theme.colors.btnPush_Bk.argb == 0xFF102030)
    Swag.assert(theme.metrics.btnPush_Height == 44)
    Swag.assert(theme.rects.btnPush_Normal.rect.y == 29)
    Swag.assert(theme.rects.btnPush_Normal.corner == 5)
    Swag.assert(theme.rects.btnPush_Hot.rect.x == 1)
    Swag.assert(theme.rects.btnPush_Hot.corner == 5)

    // An unknown key is a sheet error carrying its line.
    discard catch theme.applySheet("/ThemeColors\nnotAColor 0xFF000000\n") as err
    Swag.assert(err != null)
    Swag.assert(err is Core.Errors.SyntaxError)
}

// A sheet resource resolves through a bundle, embedded content included.
#test
{
    const CustomSheet = "/ThemeMetrics\nbtnPush_Width 123\n"

    var res: Resources.Bundle
    res.addEmbedded("themes/custom.tweak", cast(const [..] u8) CustomSheet)

    var theme: Theme
    expect theme.loadSheet(&res, "themes/custom.tweak")
    Swag.assert(theme.metrics.btnPush_Width == 123)

    discard catch theme.loadSheet(&res, "themes/missing.tweak") as err
    Swag.assert(err != null)
    Swag.assert(err is Core.Errors.FileNotFoundError)
}
