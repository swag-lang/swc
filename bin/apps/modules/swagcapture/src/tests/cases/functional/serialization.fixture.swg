#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

func serializationFixturePath(name: string)->String => Path.combine(testSourceRoot(#curlocation), "datas", name)

// This checked-in SCC is the on-disk contract. Unlike a save/load round trip produced by one
// compiler invocation, it fails when a rename or serialization change alters a published id.
#test
{
    const PathName = "capture-all-forms.scc"
    let path = serializationFixturePath(PathName)
    Swag.require(File.exists(path))
    Swag.require(expect Scc.hasSignature(path))

    var container: Scc.Reader
    expect container.initialize(path)
    Swag.require(container.kind() == expect Guid128.parse("4a67acc2-5930-4e81-81dc-d12675bc6deb"))
    Swag.require(container.manifest().profileVersion == 1)
    container.close()

    let capture = expect Capture.load(path)
    defer Memory.delete(capture)
    Swag.require(capture.loadIssues == 0)
    Swag.require(capture.width == 128)
    Swag.require(capture.height == 96)
    Swag.require(capture.widthOrg == 128)
    Swag.require(capture.heightOrg == 96)
    Swag.require(capture.backImg.isValid())
    Swag.require(capture.backImgOriginal.isValid())
    Swag.require(capture.backImg.pixelColor(0, 0).argb == ColorBlue.argb)
    Swag.require(capture.backImgOriginal.pixelColor(0, 0).argb == ColorGreen.argb)
    Swag.require(capture.preview.isValid())
    Swag.require(capture.preview.width == 16)
    Swag.require(capture.preview.height == 12)
    Swag.require(capture.preview.pixelColor(0, 0).argb == ColorRed.argb)

    Swag.require(capture.title == "Serialization Contract")
    Swag.require(capture.sourceKind == .Screen)
    let expectedTime = Time.DateTime{year: 2026, month: 8, day: 30, hour: 6, minute: 45, second: 12}
    Swag.require(capture.capturedAt == expectedTime)
    Swag.require(capture.sourceApplication == "fixture-app")
    Swag.require(capture.sourceExecutable == "C:\\Fixtures\\fixture-app.exe")
    Swag.require(capture.sourceWindowTitle == "Fixture Window")
    Swag.require(capture.sourceWindowClass == "FixtureWindowClass")
    Swag.require(capture.tags.count == 2)
    Swag.require(capture.tags[0] == "serialization")
    Swag.require(capture.tags[1] == "all-forms")
    Swag.require(capture.favorite)
    Swag.require(capture.rating == 5)

    Swag.require(capture.forms.count == 9)
    Swag.require(Swag.kindOf(capture.forms[0]) == #typeof(FormShape))
    Swag.require(Swag.kindOf(capture.forms[1]) == #typeof(FormLine))
    Swag.require(Swag.kindOf(capture.forms[2]) == #typeof(FormArrow))
    Swag.require(Swag.kindOf(capture.forms[3]) == #typeof(FormPolygon))
    Swag.require(Swag.kindOf(capture.forms[4]) == #typeof(FormDraw))
    Swag.require(Swag.kindOf(capture.forms[5]) == #typeof(FormText))
    Swag.require(Swag.kindOf(capture.forms[6]) == #typeof(FormStep))
    Swag.require(Swag.kindOf(capture.forms[7]) == #typeof(FormImage))
    Swag.require(Swag.kindOf(capture.forms[8]) == #typeof(FormCallout))

    let shape = assume cast(*FormShape, capture.forms[0])
    Swag.require(shape.x == 2 and shape.y == 3 and shape.w == 20 and shape.h == 18)
    Swag.require(shape.kind == .RoundRectangle)
    Swag.require(shape.roundSize == 17)
    Swag.require(shape.borderSize == 6)
    Swag.require(shape.backColor == ColorYellow)

    let line = assume cast(*FormLine, capture.forms[1])
    Swag.require(line.xa == 5 and line.ya == 7 and line.xb == 91 and line.yb == 33)
    Swag.require(line.bezier and line.xc == 38 and line.yc == 4)
    Swag.require(line.beginCap == .Round and line.endCap == .Triangle)

    let arrow = assume cast(*FormArrow, capture.forms[2])
    Swag.require(arrow.xa == 8 and arrow.ya == 82 and arrow.xb == 113 and arrow.yb == 54)
    Swag.require(arrow.startSize == 7 and arrow.endSize == 13)

    let polygon = assume cast(*FormPolygon, capture.forms[3])
    Swag.require(polygon.points.count == 3)
    Swag.require(polygon.points[0] == Math.Vector2{18, 18})
    Swag.require(polygon.points[2] == Math.Vector2{41, 62})
    Swag.require(polygon.bezier)

    let draw = assume cast(*FormDraw, capture.forms[4])
    Swag.require(draw.points.count == 3)
    Swag.require(draw.anchorSize == 9)
    Swag.require(draw.subKind == .PixSel)

    let text = assume cast(*FormText, capture.forms[5])
    Swag.require(text.text == "fixture text")
    Swag.require(text.fontName == "Arial")
    Swag.require(text.fontSize == 27)
    Swag.require(text.boldSize == 2)
    Swag.require(text.alignHorz == .RightBottom)
    Swag.require(text.alignVert == .LeftTop)

    let step = assume cast(*FormStep, capture.forms[6])
    Swag.require(step.index == 7)
    Swag.require(step.kind == .RoundRectangle)
    Swag.require(step.typeIndex == .LetterDown)

    let image = assume cast(*FormImage, capture.forms[7])
    Swag.require(image.kind == .Image)
    Swag.require(image.place == .Free)
    Gui.Testing.assertRect(image.freePos, 4, 5, 11, 13)
    Swag.require(image.image.isValid())
    Swag.require(image.image.width == 3 and image.image.height == 2)
    Swag.require(image.image.pixelColor(0, 0).argb == Argb.Magenta)

    let callout = assume cast(*FormCallout, capture.forms[8])
    Swag.require(callout.text == "fixture callout")
    Swag.require(callout.roundSize == 19)
    Swag.require(callout.tailX == 87 and callout.tailY == 91)
    Swag.require(callout.textColor.argb == Argb.Cyan)
}

// A second persisted document protects the library-only load path and Unicode metadata.
#test
{
    let path = serializationFixturePath("capture-library-metadata.scc")
    Swag.require(File.exists(path))

    let preview = expect Capture.load(path, preview: true)
    defer Memory.delete(preview)
    Swag.require(preview.loadIssues == 0)
    Swag.require(preview.width == 12 and preview.height == 10)
    Swag.require(preview.forms.count == 0)
    Swag.require(not preview.backImg.isValid())
    Swag.require(preview.preview.isValid())
    Swag.require(preview.title == "Été — 東京")
    Swag.require(preview.sourceKind == .ImageFile)
    Swag.require(preview.sourceApplication == "Éditeur Δ")
    Swag.require(preview.sourceExecutable == "C:\\Outils\\éditeur.exe")
    Swag.require(preview.sourceWindowTitle == "Capture vérifiée — 東京")
    Swag.require(preview.sourceWindowClass == "Fixture.Ünicode")
    Swag.require(preview.tags.count == 2)
    Swag.require(preview.tags[0] == "été")
    Swag.require(preview.tags[1] == "東京")
    Swag.require(preview.favorite)
    Swag.require(preview.rating == 3)

    let full = expect Capture.load(path)
    defer Memory.delete(full)
    Swag.require(full.loadIssues == 0)
    Swag.require(full.forms.count == 0)
    Swag.require(full.backImg.isValid())
    Swag.require(full.backImg.width == 12 and full.backImg.height == 10)
    Swag.require(full.title == preview.title)
    Swag.require(full.sourceApplication == preview.sourceApplication)
    Swag.require(full.rating == preview.rating)
}
