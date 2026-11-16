#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

// A dark application keeps a long light document's ground and an undistorted minimal thumb on hover.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(520, 300)
    host.theme.setDark()
    host.notify(.ThemeChanged)
    host.root.backgroundStyle = .View
    host.root.style.setStyleSheetColors("view_Bk 0xFFFBF8F1")
    let scroll = Wnd.create'ScrollWnd(&host.root, "", {0, 0, 520, 300})
    scroll.updateFlags(.DisableHorizontal)
    let view = scroll.createView'Wnd()
    let title = Label.create(view, "A page keeps its own ground", {24, 24, 440, 40})
    title.style.setStyleSheetColors("label_Text 0xFF222222")
    scroll.setScrollSize(0, 100_000)
    Swag.require(scroll.sizeBoxV == host.theme.metrics.scrollBar_BoxMinSize)
    let track = scroll.verticalThumbRect(true)
    host.moveMouse(scroll.localToSurface(track.center()))
    host.finishAnimations()
    Swag.require(scroll.isHotBarV)

    var image = host.renderSettled(&host.root)
    let trackColor = image.pixelColor(cast(s32, track.horzCenter()), cast(s32, track.vertCenter()))
    Swag.require(trackColor.argb != 0xFFFBF8F1 and trackColor.contrastRatio(Color.fromArgb(0xFFFBF8F1)) < 1.4)
    Pixel.Testing.assertImageGolden(&image, "scroll.hover.light-content.encre")
}

// A light application keeps a translucent track while the minimal thumb of a wide dark view is dragged.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(520, 220)
    host.theme.setLight()
    host.notify(.ThemeChanged)
    host.root.backgroundStyle = .View
    host.root.style.setStyleSheetColors("view_Bk 0xFF17181C")
    let scroll = Wnd.create'ScrollWnd(&host.root, "", {0, 0, 520, 220})
    let view = scroll.createView'Wnd()
    let title = Label.create(view, "The thumb carries the gesture", {24, 24, 440, 40})
    title.style.setStyleSheetColors("label_Text 0xFFECEDF0")
    scroll.setScrollSize(100_000, 0)
    Swag.require(scroll.sizeBoxH == host.theme.metrics.scrollBar_BoxMinSize)
    let thumb = scroll.horizontalThumbRect()
    host.moveMouse(scroll.localToSurface(thumb.center()))
    host.finishAnimations()
    host.mouseDown(scroll.localToSurface(thumb.center()))
    defer host.mouseUp(scroll.localToSurface(thumb.center()))
    Swag.require(scroll.isPressedH and scroll.isMoving)

    var image = host.renderSettled(&host.root)
    let track = scroll.horizontalThumbRect(true)
    let trackColor = image.pixelColor(cast(s32, track.horzCenter()), cast(s32, track.vertCenter()))
    Swag.require(trackColor.argb != 0xFF17181C and trackColor.contrastRatio(Color.fromArgb(0xFF17181C)) < 1.4)
    Pixel.Testing.assertImageGolden(&image, "scroll.drag.dark-content.paper")
}
