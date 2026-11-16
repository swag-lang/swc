#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

// Show and load a dropped document while saved-path resolution is held by an unavailable drive.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var release: Sync.Event
    release.init(manual: true)
    var held:    Swag.Task
    var journey: ScopeJourney
    journey.setup()
    let file   = journey.copyData("viewer.html", "dropped.html")
    let window = journey.window
    window.privacy.scan.executor.start(.Background)
    held.submit(func|gate = &release|() { gate.wait() }, executor: &window.privacy.scan.executor)
    defer release.signal()

    window.recent.add(Path.combine(journey.root, "unavailable", "old.html"))
    window.recentOpened.add(HomeNow)
    window.privacy.sanitize()
    Swag.require(window.privacy.scan.started and not window.privacy.scan.isDone())
    let arguments: [2] string = [Env.executablePath(), file]
    window.queueFile(viewerStartupFile(arguments))
    journey.waitForFile(file)
    Swag.require(not window.privacy.scan.isDone())
    Swag.require(window.choices[window.activeChoiceIndex].key == "html")

    release.signal()
    held.wait()
    journey.waitFor("saved paths resolved", func|window|()->bool => not window.privacy.scan.started)
}
