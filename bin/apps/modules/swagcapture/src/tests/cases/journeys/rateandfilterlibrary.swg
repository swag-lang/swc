#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Rate and favorite one capture, narrow the library, then remove the filters.
#[Swag.TestTag("integration.application.journey")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let main = journey.main
    for title in ["Draft", "Review", "Published"]
    {
        discard journey.newCapture()
        let capture = unwrap main.editWnd.getCapture()
        capture.title = title
        capture.changed = true
        main.saveCapture(capture)
    }

    journey.openLibrary(3)
    let library = main.libWnd
    var chosen = Swag.U32.Max
    for item, index in library.view.items where item.capture and item.capture.title == "Review" do
        chosen = cast(u32, index)
    Swag.require(chosen != Swag.U32.Max)
    let markedFile = library.view.items[chosen].fi.fullName
    library.view.setFocusItem(chosen)
    library.sendCommandEvent(ActionLibSel.Rate5)
    library.toggleSelectedFavorite()
    journey.waitFor("marked capture", func|library|()->bool => library.view.items[library.view.focusItem].capture!.rating == 5 and
                                                         library.view.items[library.view.focusItem].capture!.favorite)

    library.sendCommandEvent(ActionLibFilter.FavoritesOnly)
    journey.waitFor("favorite filter", func|library|()->bool => library.favoritesOnly and
                                                          library.view.items.count == 1 and
                                                          library.view.items[0].capture!.title == "Review")
    library.sendCommandEvent(ActionLibFilter.Rating5)
    Swag.require(library.minimumRating == 5 and library.view.items.count == 1)
    library.sendCommandEvent(ActionLibFilter.Reset)
    journey.waitFor("all captures", func|library|()->bool => library.view.items.count == 3 and
                                                       not library.favoritesOnly and library.minimumRating == 0)
    journey.waitFor("metadata written", func||()->bool => not g_CaptureSaves.metadataPending and
                                                          g_CaptureSaves.metadataWaiting.isEmpty())
    let stored = expect Capture.load(markedFile, preview: true)
    defer Memory.delete(stored)
    Swag.require(stored.rating == 5 and stored.favorite)
}
