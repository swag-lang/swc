#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

// A history returns the places in the order they were left, and comes back through them.
#test
{
    var history: Viewer.History's32
    Swag.require(not history.canGoBack() and not history.canGoForward())

    history.visit(1)
    history.visit(2)
    Swag.require(history.canGoBack() and not history.canGoForward())

    // Standing at 3: back gives 2, then 1, keeping where each return started from.
    Swag.require(history.back(3) == 2 and history.canGoForward())
    Swag.require(history.back(2) == 1)
    Swag.require(not history.canGoBack())
    Swag.require(history.forward(1) == 2 and history.forward(2) == 3)
    Swag.require(history.canGoBack() and not history.canGoForward())
}

// A jump made after a return starts a new branch, and a new document starts a new history.
#test
{
    var history: Viewer.History's32
    history.visit(1)
    history.visit(2)
    Swag.require(history.back(3) == 2 and history.canGoForward())

    history.visit(2)
    Swag.require(not history.canGoForward())
    Swag.require(history.back(9) == 2 and history.back(2) == 1)

    history.clear()
    Swag.require(not history.canGoBack() and not history.canGoForward())
}

// Each direction forgets its oldest place beyond the limit, whichever way it was filled.
#test
{
    const Limit = cast(s32, Viewer.HistoryLimit)
    var history: Viewer.History's32
    for place in Limit + 10 do
        history.visit(place)
    Swag.require(history.backVisits.count == Limit)
    Swag.require(history.backVisits.front() == 10 and history.backVisits.back() == Limit + 9)

    // Walking all the way back fills the other direction with exactly as many places.
    var current = Limit + 10
    while history.canGoBack() do
        current = history.back(current)
    Swag.require(current == 10 and history.forwardVisits.count == Limit)
    while history.canGoForward() do
        current = history.forward(current)
    Swag.require(current == Limit + 10 and history.backVisits.count == Limit)
}

// A place may own storage: the history keeps its own copy of what it is given.
#test
{
    var history: Viewer.History'String
    scope
    {
        var chapter: String = "chapter-one#arrival"
        history.visit(chapter)
        chapter = "overwritten"
    }

    let returned = history.back("chapter-two")
    Swag.require(returned == "chapter-one#arrival")
    Swag.require(history.forward(returned) == "chapter-two")
}

// The history and page keys are exact chords: another modifier, a release, or another key is
// left to whoever owns it.
#test
{
    func pressed(key: Input.Key, modifiers: Input.KeyModifiers)->KeyEvent => {kind: .Pressed, key: key, modifiers: modifiers}

    var back    = pressed(.Left, .Alt)
    var forward = pressed(.Right, .Alt)
    Swag.require(Viewer.historyKeyDirection(&back) == -1 and Viewer.historyKeyDirection(&forward) == 1)

    var plain   = pressed(.Left, .None)
    var chord   = pressed(.Left, Input.KeyModifiers.Alt | .Shift)
    var other   = pressed(.Up, .Alt)
    var release = KeyEvent{kind: .Released, key: .Left, modifiers: .Alt}
    for evt in [&plain, &chord, &other, &release] do
        Swag.require(Viewer.historyKeyDirection(evt) == 0)

    var previous = pressed(.PageUp, .Control)
    var next     = pressed(.PageDown, .Control)
    Swag.require(Viewer.pageKeyDirection(&previous) == -1 and Viewer.pageKeyDirection(&next) == 1)

    var bare   = pressed(.PageDown, .None)
    var arrow  = pressed(.Down, .Control)
    var lifted = KeyEvent{kind: .Released, key: .PageDown, modifiers: .Control}
    for evt in [&bare, &arrow, &lifted] do
        Swag.require(Viewer.pageKeyDirection(evt) == 0)
}

// The zoom keys step by one notch inside the range and Ctrl 0 returns to the actual size.
#test
{
    func control(key: Input.Key)->KeyEvent => {kind: .Pressed, key: key, modifiers: .Control}

    for key in [Input.Key.Add, .OemPlus]
    {
        var evt = control(key)
        Swag.require(Viewer.isZoomKey(&evt))
        Swag.require(Viewer.zoomAfterKey(&evt, 100) == 100 + Viewer.ZoomStep)
        Swag.require(Viewer.zoomAfterKey(&evt, Viewer.MaxZoom) == Viewer.MaxZoom)
    }

    for key in [Input.Key.Subtract, .OemMinus]
    {
        var evt = control(key)
        Swag.require(Viewer.isZoomKey(&evt))
        Swag.require(Viewer.zoomAfterKey(&evt, 100) == 100 - Viewer.ZoomStep)
        Swag.require(Viewer.zoomAfterKey(&evt, Viewer.MinZoom) == Viewer.MinZoom)
    }

    var reset = control(.D0)
    Swag.require(Viewer.isZoomKey(&reset) and Viewer.zoomAfterKey(&reset, 275) == 100)

    var unbound  = control(.D1)
    var bare     = KeyEvent{kind: .Pressed, key: .Add}
    var released = KeyEvent{kind: .Released, key: .Add, modifiers: .Control}
    for evt in [&unbound, &bare, &released] do
        Swag.require(not Viewer.isZoomKey(evt))

    // The lens asks for the same levels as the keys, and never leaves the range.
    Swag.require(Viewer.zoomTarget(.In, 100) == 125 and Viewer.zoomTarget(.Out, 100) == 75)
    Swag.require(Viewer.zoomTarget(.Reset, 250) == 100)
    Swag.require(Viewer.zoomTarget(.In, Viewer.MaxZoom) == Viewer.MaxZoom)
    Swag.require(Viewer.zoomTarget(.Out, Viewer.MinZoom) == Viewer.MinZoom)
    Swag.require(Viewer.zoomOut(Viewer.MinZoom + 10) == Viewer.MinZoom)
    Swag.require(Viewer.clampZoom(10) == Viewer.MinZoom and Viewer.clampZoom(900) == Viewer.MaxZoom)
    Swag.require(Viewer.zoomText(125) == "125 %")
}

// Readouts spell a page, a count and an encoding one way for every viewer.
#test
{
    Swag.require(Viewer.pageText(0, 12) == "1 / 12" and Viewer.pageText(11, 12) == "12 / 12")
    Swag.require(Viewer.pageText(40, 12) == "12 / 12" and Viewer.pageText(0, 0) == "0 / 0")

    Swag.require(Viewer.groupThousands(0) == "0" and Viewer.groupThousands(999) == "999")
    Swag.require(Viewer.groupThousands(1280) == "1 280" and Viewer.groupThousands(1_000_000) == "1 000 000")
    Swag.require(Viewer.groupThousands("-272716322") == "-272 716 322")
    Swag.require(Viewer.groupThousands("-999") == "-999" and Viewer.groupThousands("") == "")
    Swag.require(Viewer.groupThousands("0x1F40") == "0x1F40" and Viewer.groupThousands("12.5") == "12.5")

    const Names: [6] { encoding: Text.Encoding, name: string } = [
        {.Utf8,        "UTF-8"},
        {.Utf16Le,     "UTF-16 LE"},
        {.Utf16Be,     "UTF-16 BE"},
        {.Utf32Le,     "UTF-32 LE"},
        {.Utf32Be,     "UTF-32 BE"},
        {.Windows1252, "Windows-1252"}]
    for row in Names do
        Swag.require(Viewer.encodingName(row.encoding) == row.name)
}
