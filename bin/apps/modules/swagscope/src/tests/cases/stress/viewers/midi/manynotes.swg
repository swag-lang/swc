#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// Parse and browse a score whose notes vastly outnumber the visible piano-roll cells.
#[Swag.TestTag("stress")]
#test
{
    const NoteCount = 20_000'u32
    let file = Testing.tempFilePath("scope-many-notes-", ".mid")
    defer discard catch File.delete(file)
    var bytes: Array'u8
    bytes.add(cast(const [..] u8, "MThd"))
    bytes.add([0'u8, 0, 0, 6, 0, 0, 0, 1, 1, 0xE0])
    bytes.add(cast(const [..] u8, "MTrk"))
    let trackSize = NoteCount * 8 + 4
    bytes.add([cast(u8, (trackSize >> 24) & 0xFF), cast(u8, (trackSize >> 16) & 0xFF),
               cast(u8, (trackSize >> 8) & 0xFF), cast(u8, trackSize & 0xFF)])
    for index in NoteCount
    {
        let key = cast(u8, 60 + index % 12)
        bytes.add([0'u8, 0x90, key, 100, 1, 0x80, key, 0])
    }
    bytes.add([0'u8, 0xFF, 0x2F, 0])
    expect File.writeAllBytes(file, bytes.toSlice())

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    var session = openTestViewer(Midi.viewerPlugin(), &host.root, file,
                                 commandParent: &host.root, infoParent: &host.root)
    Swag.require(session.view != null)
    let view = assume cast(*Midi.Panel, session.view)
    completeViewerBackgroundLoad(&host, &view.load)
    Swag.require(view.roll.document.notes.count == NoteCount and
                 view.roll.document.tracks[0].noteCount == NoteCount)
    view.dockStyle = .Center
    host.root.applyLayout()
    view.roll.zoomToFit()
    var image = host.render(&host.root)
    Swag.require(image.isValid() and view.roll.fit)

    view.roll.zoomIn()
    view.roll.setTrack(0)
    image = host.render(&host.root)
    Swag.require(image.isValid() and not view.roll.fit and
                 view.roll.selectedNoteCount() == NoteCount)
}
