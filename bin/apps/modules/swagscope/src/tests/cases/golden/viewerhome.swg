#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

// The home is a page of what was read lately: the last file as a card with its picture, how far
// it was read and the action that takes it up again; the files before it as tiles with their
// pictures and times; the folders explored lately as chips. The tile under the pointer is ringed
// and offers its removal. One picture at rest and one in use.
#[Swag.TestTag("golden")]
#test
{
    let light  = true
    var host: Testing.HeadlessHost
    let window = homeWindow(&host, light, height: 720)
    var point: ViewerResumePoint
    point.file     = window.recent[0]
    point.progress = 0.38
    window.resumePoints.add(#move point)
    window.home.refresh()

    let home = window.home
    Swag.require(home.isLocallyVisible() and home.rows.count == 6 and home.places.count == 2)
    Swag.require(ViewerHome.openedText(home.rows[0].opened, HomeNow) == "17:42")
    Swag.require(ViewerHome.openedText(home.rows[3].opened, HomeNow) == appStrings().home_Yesterday)
    Swag.require(Format.toString(appStrings().home_ResumeShare, 38) == home.resumeButton.text())
    Swag.require(home.restartButton.isLocallyVisible() and home.clearButton.isLocallyVisible())
    Swag.require(home.openButton.isLocallyVisible() and home.exploreButton.isLocallyVisible())
    Swag.require(home.openButton.text() == appStrings().home_OpenFile)

    // Every part shares the left edge of the column, and the Clear menu ends the tiles' label.
    let place = home.layout()
    Swag.require(place.hero.x == place.column.x and place.recentLabel.x == place.column.x)
    Swag.require(home.pictureRect(1).x == place.column.x and home.placeRect(0).x + ViewerHome.PlaceInset == place.column.x)
    Swag.require(home.clearButton.position.right() == place.recentLabel.right() and place.showPlaces)
    Swag.require(home.resumeButton.position.x == place.heroText.x)
    Swag.require(home.openButton.position.y == place.actions and home.exploreButton.position.right() == place.column.right())
    Swag.require(home.openButton.position.x - place.column.x > Painter.measureString(appStrings().home_Invite, home.theme().createDefaultFont(ViewerHome.FontSize)).width)
    Swag.require(host.mouseTargetAt(home.localToSurface(home.openButton.position.center())) == home.openButton)
    Swag.require(host.mouseTargetAt(home.localToSurface(home.exploreButton.position.center())) == home.exploreButton)
    for index in 1 until home.rows.count do
        Swag.require(home.rows[index].attempted)

    var rest = host.renderSettled(window)
    assertScopeImageGolden(&rest, "home.paper")

    host.moveMouse(home.localToSurface(home.rowRect(2).center()))
    Swag.require(home.hovered == 2 and home.pointerIn and home.removeButton.isLocallyVisible())
    home.invalidate()
    var hover = host.render(window)
    assertScopeImageGolden(&hover, "home.hover.paper")
}
