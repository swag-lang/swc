#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Gui.Testing, Viewers

// An office document names its title, its author, the day it was created and the program that
// saved it: Office Open XML in its core and application parts, OpenDocument in its meta part,
// whose generator loses its build details.
#test
{
    let docx = Package.DocumentProperties.read(scopeTestDataPath("viewer.poi-sample.docx"))
    Swag.require(docx.title == "Test Document" and docx.author == "Nick Burch", docx.title)
    Swag.require(docx.created == "2008-01-04" and docx.application == "Microsoft Office Word", docx.created)

    let ods = Package.DocumentProperties.read(scopeTestDataPath("viewer.monthly-budget.ods"))
    Swag.require(ods.author == "Johannes" and ods.application == "LibreOfficeDev/26.8.0.0.alpha0", ods.application)

    // A package without those parts, or a file that is no package, says nothing.
    Swag.require(Package.DocumentProperties.read(scopeTestDataPath("viewer.docx")).isEmpty())
    Swag.require(Package.DocumentProperties.read(scopeTestDataPath("viewer.png")).isEmpty())
}

// The information sheet of an opened office document gives what its package says of it.
#test
{
    var host: HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.poi-sample.pptx"), false)
    let view   = assume cast(*Pptx.Panel, window.instances[window.activeChoiceIndex].view)
    let sheet  = InfoSheet.create(&host.root)
    view.describeInformation(sheet)
    let text = sheet.text()
    Swag.require(Utf8.contains(text, "Title\nSlideShow Sample") and Utf8.contains(text, "Author\nNick Burch"), text)
    Swag.require(Utf8.contains(text, "Created\n2008-01-04") and Utf8.contains(text, "Application\nMicrosoft Office PowerPoint"), text)
}
