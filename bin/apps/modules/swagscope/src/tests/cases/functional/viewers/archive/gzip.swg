#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Gui.Testing, Viewers

// TAR.GZ files enter the shared Explorer archive listing with indexed member rows.
#test
{
    let listing = expect ExplorerListing.load(scopeTestDataPath("viewer.field-kit.tar.gz"))
    Swag.require(listing.isArchive and listing.archive.entries.count == 3)
    let notes = listing.children("notes/")
    Swag.require(notes.count == 1 and notes[0].path == "notes/README.txt")
    Swag.require(notes[0].archiveIndex < listing.archive.entries.count)
}
