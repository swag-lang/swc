#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

func serializationFixturePath(name: string)->String
{
    return Path.combine(Path.directoryName(#curlocation.fileName)!, "datas", name)
}

// This checked-in SCC is the on-disk contract. Unlike a save/load round trip produced by one
// compiler invocation, it fails when a rename or serialization change alters a published id.
#test
{
    const PathName = "capture-all-forms.scc"
    let path = serializationFixturePath(PathName)
    Swag.assert(File.exists(path))
    Swag.assert(expect Scc.hasSignature(path))

    var container: Scc.Reader
    expect container.initialize(path)
    Swag.assert(container.kind() == expect Guid128.parse("4a67acc2-5930-4e81-81dc-d12675bc6deb"))
    Swag.assert(container.manifest().profileVersion == 1)
    container.close()

    let capture = expect Capture.load(path)!
    defer Memory.delete(capture)
    Swag.assert(capture.loadIssues == 0)
    Swag.assert(capture.width == 128)
    Swag.assert(capture.height == 96)
    Swag.assert(capture.widthOrg == 128)
    Swag.assert(capture.heightOrg == 96)
    Swag.assert(capture.backImg.isValid())
    Swag.assert(capture.backImgOriginal.isValid())
    Swag.assert(capture.backImg.pixelColor(0, 0).argb == ColorBlue.argb)
    Swag.assert(capture.backImgOriginal.pixelColor(0, 0).argb == ColorGreen.argb)
    Swag.assert(capture.preview.isValid())
    Swag.assert(capture.preview.width == 16)
    Swag.assert(capture.preview.height == 12)
    Swag.assert(capture.preview.pixelColor(0, 0).argb == ColorRed.argb)

    Swag.assert(capture.title == "Serialization Contract")
    Swag.assert(capture.sourceKind == .Screen)
    let expectedTime = Time.DateTime{year: 2026, month: 8, day: 30, hour: 6, minute: 45, second: 12}
    Swag.assert(capture.capturedAt == expectedTime)
    Swag.assert(capture.sourceApplication == "fixture-app")
    Swag.assert(capture.sourceExecutable == "C:\\Fixtures\\fixture-app.exe")
    Swag.assert(capture.sourceWindowTitle == "Fixture Window")
    Swag.assert(capture.sourceWindowClass == "FixtureWindowClass")
    Swag.assert(capture.tags.count == 2)
    Swag.assert(capture.tags[0] == "serialization")
    Swag.assert(capture.tags[1] == "all-forms")
    Swag.assert(capture.favorite)
    Swag.assert(capture.rating == 5)

    Swag.assert(capture.forms.count == 9)
    Swag.assert(Swag.kindOf(capture.forms[0]) == #typeof(FormShape))
    Swag.assert(Swag.kindOf(capture.forms[1]) == #typeof(FormLine))
    Swag.assert(Swag.kindOf(capture.forms[2]) == #typeof(FormArrow))
    Swag.assert(Swag.kindOf(capture.forms[3]) == #typeof(FormPolygon))
    Swag.assert(Swag.kindOf(capture.forms[4]) == #typeof(FormDraw))
    Swag.assert(Swag.kindOf(capture.forms[5]) == #typeof(FormText))
    Swag.assert(Swag.kindOf(capture.forms[6]) == #typeof(FormStep))
    Swag.assert(Swag.kindOf(capture.forms[7]) == #typeof(FormImage))
    Swag.assert(Swag.kindOf(capture.forms[8]) == #typeof(FormCallout))

    let shape = cast(*FormShape) capture.forms[0].buffer
    Swag.assert(shape.x == 2 and shape.y == 3 and shape.w == 20 and shape.h == 18)
    Swag.assert(shape.kind == .RoundRectangle)
    Swag.assert(shape.roundSize == 17)
    Swag.assert(shape.borderSize == 6)
    Swag.assert(shape.backColor == ColorYellow)

    let line = cast(*FormLine) capture.forms[1].buffer
    Swag.assert(line.xa == 5 and line.ya == 7 and line.xb == 91 and line.yb == 33)
    Swag.assert(line.bezier and line.xc == 38 and line.yc == 4)
    Swag.assert(line.beginCap == .Round and line.endCap == .Triangle)

    let arrow = cast(*FormArrow) capture.forms[2].buffer
    Swag.assert(arrow.xa == 8 and arrow.ya == 82 and arrow.xb == 113 and arrow.yb == 54)
    Swag.assert(arrow.startSize == 7 and arrow.endSize == 13)

    let polygon = cast(*FormPolygon) capture.forms[3].buffer
    Swag.assert(polygon.points.count == 3)
    Swag.assert(polygon.points[0] == Math.Vector2{18, 18})
    Swag.assert(polygon.points[2] == Math.Vector2{41, 62})
    Swag.assert(polygon.bezier)

    let draw = cast(*FormDraw) capture.forms[4].buffer
    Swag.assert(draw.points.count == 3)
    Swag.assert(draw.anchorSize == 9)
    Swag.assert(draw.subKind == .PixSel)

    let text = cast(*FormText) capture.forms[5].buffer
    Swag.assert(text.text == "fixture text")
    Swag.assert(text.fontName == "Arial")
    Swag.assert(text.fontSize == 27)
    Swag.assert(text.boldSize == 2)
    Swag.assert(text.alignHorz == .RightBottom)
    Swag.assert(text.alignVert == .LeftTop)

    let step = cast(*FormStep) capture.forms[6].buffer
    Swag.assert(step.index == 7)
    Swag.assert(step.kind == .RoundRectangle)
    Swag.assert(step.typeIndex == .LetterDown)

    let image = cast(*FormImage) capture.forms[7].buffer
    Swag.assert(image.kind == .Image)
    Swag.assert(image.place == .Free)
    Gui.Testing.assertRect(image.freePos, 4, 5, 11, 13)
    Swag.assert(image.image.isValid())
    Swag.assert(image.image.width == 3 and image.image.height == 2)
    Swag.assert(image.image.pixelColor(0, 0).argb == Argb.Magenta)

    let callout = cast(*FormCallout) capture.forms[8].buffer
    Swag.assert(callout.text == "fixture callout")
    Swag.assert(callout.roundSize == 19)
    Swag.assert(callout.tailX == 87 and callout.tailY == 91)
    Swag.assert(callout.textColor.argb == Argb.Cyan)
}

// A second persisted document protects the library-only load path and Unicode metadata.
#test
{
    let path = serializationFixturePath("capture-library-metadata.scc")
    Swag.assert(File.exists(path))

    let preview = expect Capture.load(path, preview: true)!
    defer Memory.delete(preview)
    Swag.assert(preview.loadIssues == 0)
    Swag.assert(preview.width == 12 and preview.height == 10)
    Swag.assert(preview.forms.count == 0)
    Swag.assert(!preview.backImg.isValid())
    Swag.assert(preview.preview.isValid())
    Swag.assert(preview.title == "Été — 東京")
    Swag.assert(preview.sourceKind == .ImageFile)
    Swag.assert(preview.sourceApplication == "Éditeur Δ")
    Swag.assert(preview.sourceExecutable == "C:\\Outils\\éditeur.exe")
    Swag.assert(preview.sourceWindowTitle == "Capture vérifiée — 東京")
    Swag.assert(preview.sourceWindowClass == "Fixture.Ünicode")
    Swag.assert(preview.tags.count == 2)
    Swag.assert(preview.tags[0] == "été")
    Swag.assert(preview.tags[1] == "東京")
    Swag.assert(preview.favorite)
    Swag.assert(preview.rating == 3)

    let full = expect Capture.load(path)!
    defer Memory.delete(full)
    Swag.assert(full.loadIssues == 0)
    Swag.assert(full.forms.count == 0)
    Swag.assert(full.backImg.isValid())
    Swag.assert(full.backImg.width == 12 and full.backImg.height == 10)
    Swag.assert(full.title == preview.title)
    Swag.assert(full.sourceApplication == preview.sourceApplication)
    Swag.assert(full.rating == preview.rating)
}
