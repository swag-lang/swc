#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

// Release the input driver and path temporaries before dropping the native application.
#[Swag.NoInline]
func editExplorerLocation(journey: *ScopeJourney)
{
    let first = Path.combine(journey.root, "First")
    let next  = Path.combine(journey.root, "Next folder")
    expect Directory.create(first)
    expect Directory.create(Path.combine(next, "Destination child"), recurse: true)
    journey.window.openExplorer(first)
    let explorer = unwrap journey.window.explorer
    journey.waitFor("first folder", func|explorer, first = first.toString()|()->bool => not explorer.load.started and Path.equals(explorer.listing.path, first))

    var input   = Testing.DesktopInput.create(&journey.app, journey.surface)
    let address = explorer.address
    let crumb   = address.breadcrumb
    let point   = crumb.localToSurface(crumb.items.backPtr().bodyRect.center())
    input.moveTo(crumb, point)
    var screen = point
    journey.surface.surfaceToScreen(&screen)
    input.clickDesktopPoint(screen)
    Swag.require(address.edit.isLocallyVisible() and Path.equals(address.edit.text(), first))
    let selection = address.edit.selection()
    Swag.require(selection.start == 0 and selection.end == address.edit.text().count)

    address.edit.setText("../Next folder")
    var outside = explorer.grid.surfaceRect().center()
    journey.surface.surfaceToScreen(&outside)
    input.clickDesktopPoint(outside)
    Swag.require(not address.edit.isLocallyVisible() and Path.equals(explorer.listing.path, first))

    input.clickDesktopPoint(screen)
    Swag.require(address.edit.isLocallyVisible() and Path.equals(address.edit.text(), first))
    address.edit.setText("missing folder")
    input.shortcut(.Return, .None)
    Swag.require(address.edit.isLocallyVisible() and not address.edit.isValid())
    Swag.require(Path.equals(explorer.listing.path, first))
    address.edit.setText("../Next folder")
    input.shortcut(.Return, .None)

    // The listing identifies the destination even when the native path keeps its '..' component.
    journey.waitFor("edited folder", func|explorer|()->bool => not explorer.load.started and
                                                               explorer.entries.count == 1 and
                                                               explorer.entries[0].name == "Destination child")
    Swag.require(not address.edit.isLocallyVisible())
}

// The native caption leaves the location clickable, and a rejected address stays editable.
#[Swag.TestTag("integration.desktop.input")]
#test
{
    var journey: ScopeJourney
    journey.setup()
    editExplorerLocation(&journey)
}
