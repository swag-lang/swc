#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// A caption decides the width of a button that was created without one, and the theme
// width stays the floor under a short one.
#test
{
    var host: Testing.HeadlessHost
    host.setup(600, 300)
    defer host.shutdown()

    let metrics = host.root.themeMetrics()
    let short   = PushButton.create(&host.root, "OK")
    let long    = PushButton.create(&host.root, "Create an encrypted container right now")

    @assert(short.measure({}).preferred.x == metrics.btnPush_Width)
    @assert(long.measure({}).preferred.x > metrics.btnPush_Width)

    // A width the caller stated is never second-guessed.
    let pinned = PushButton.create(&host.root, "Create an encrypted container right now", {0, 0, 90, 30})
    @assert(pinned.measure({}).preferred.x == 90)

    // Re-labelling is enough: the button follows the new caption on the next measure.
    let wide = long.measure({}).preferred.x
    long.setText("OK")
    @assert(long.measure({}).preferred.x == metrics.btnPush_Width)
    @assert(wide > metrics.btnPush_Width)
}

// Wrapped text answers for the width it is offered, so a paragraph reports the height it
// really needs instead of one line.
#test
{
    var host: Testing.HeadlessHost
    host.setup(600, 300)
    defer host.shutdown()

    const Sentence = "Encrypted storage that looks and behaves like a regular Windows drive and keeps working when the application closes."

    let label = Label.create(&host.root, Sentence, {}, null, .WordWrap | .AutoHeight)
    let wide  = label.measure({500, 0}).preferred
    let tight = label.measure({160, 0}).preferred
    @assert(tight.y > wide.y)
    @assert(wide.y > 0)

    // Without the wrap flag the text stays on one line whatever it is offered.
    let single = Label.create(&host.root, Sentence, {}, null, .AutoHeight)
    @assert(single.measure({160, 0}).preferred.y == single.measure({500, 0}).preferred.y)
}

// A combo box is as wide as its widest entry, not as wide as the selected one.
#test
{
    var host: Testing.HeadlessHost
    host.setup(600, 300)
    defer host.shutdown()

    let combo = ComboBox.create(&host.root)
    combo.addItem("en")
    let narrow = combo.measure({}).preferred.x
    combo.addItem("a language with a very long name indeed")
    let wide = combo.measure({}).preferred.x
    @assert(wide > narrow)
    @assert(narrow == host.root.themeMetrics().comboBox_Width)
}

// A band docked without a height is as tall as the stack it holds, and follows it when
// the text inside changes.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 300)
    defer host.shutdown()

    let band = StackLayoutCtrl.create(&host.root, .Top)
    band.dockStyle = .Top
    band.spacing   = 4

    let first = Label.create(band, "One line", {0, 0, 0, 20})
    first.dockStyle = .Top
    let second = Label.create(band, "Another line", {0, 0, 0, 20})
    second.dockStyle = .Top

    host.root.applyLayout()
    @assert(band.position.height == 44)

    // A third row raises the band; nothing had to be told a number.
    let third = Label.create(band, "A third line", {0, 0, 0, 20})
    third.dockStyle = .Top
    host.root.applyLayout()
    @assert(band.position.height == 68)
}

// A language switch moves the sizes, not only the words: this is the whole promise of
// leaving an axis unsized, checked on the module's own translated strings.
#test
{
    var host: Testing.HeadlessHost
    host.setup(500, 300)
    defer host.shutdown()
    defer discard catch applyLanguage(&host.app.resources, ReferenceLanguage)

    // "Reset to default" and its French wording are not the same width, and neither
    // button was given one: the row arranges them from what they say they need.
    let row    = StackLayoutCtrl.create(&host.root, .Left, {0, 0, 500, 40})
    let cancel = PushButton.create(row, strings().dlg_Cancel)
    let remove = PushButton.create(row, strings().prop_ResetDefault)
    row.computeLayout()
    let englishRemove = remove.position.width

    expect applyLanguage(&host.app.resources, "fr")
    cancel.setText(strings().dlg_Cancel)
    remove.setText(strings().prop_ResetDefault)
    row.computeLayout()

    @assert(remove.text() == "Rétablir la valeur par défaut")
    @assert(remove.position.width > englishRemove)

    // Nothing ends up narrower than what it has to show, in either language.
    Testing.assertContentFits(&host.root)
    expect applyLanguage(&host.app.resources, ReferenceLanguage)
    cancel.setText(strings().dlg_Cancel)
    remove.setText(strings().prop_ResetDefault)
    row.computeLayout()
    Testing.assertContentFits(&host.root)
    @assert(remove.position.width == englishRemove)
}

// A form gives its help text the height its wording needs, keeping the option as a floor.
#test
{
    var host: Testing.HeadlessHost
    host.setup(300, 400)
    defer host.shutdown()

    with var options: FormLayoutOptions
    {
        .helpHeight = 16
    }

    let form = FormLayoutCtrl.create(&host.root, options, {0, 0, 300, 400})
    discard form.addTextField("SHORT", help: "One")
    discard form.addTextField("LONG", help: "A sentence long enough that it has to be laid out over several lines inside this narrow form.")
    form.computeLayout()

    let oneLine   = form.rows[0].help!.position.height
    let manyLines = form.rows[1].help!.position.height
    @assert(oneLine >= 16)
    @assert(manyLines > oneLine)
}
