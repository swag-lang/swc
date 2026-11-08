#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

// Alternate completed and cancelled GIF takes without leaking recorder state or temporary media.
#[Swag.TestTag("integration.application.stress")]
#test
{
    var journey: CaptureJourney
    journey.setup()
    let main = journey.main
    var saved: Array'String

    for index in 8
    {
        let before = main.editWnd.getCapture()
        if index % 2 == 0
        {
            journey.recordAnimation(.Stop)
            let capture = unwrap main.editWnd.getCapture()
            Swag.require(capture.isTimed() and capture != before and File.exists(capture.file))
            for path in saved do
                Swag.require(path[] != capture.file)
            saved.add(String.from(capture.file))
        }
        else
        {
            journey.recordAnimation(.Cancel)
            Swag.require(main.editWnd.getCapture() == before)
        }
        Swag.require(g_Recorder == null and journey.app.surfaces.count == 1)
    }

    let media = expect Directory.enumerateFiles(journey.root, CaptureMediaExtension)
    Swag.require(saved.count == 4 and media.count == 4)
    for path in saved do
        Swag.require(File.exists(path[]))
}
