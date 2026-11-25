#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A custom editor for PropHeadlessAngle: a single editbox showing "<deg> deg" instead of
// expanding the struct into its 'deg' sub-field. Implemented as an IPropertyEditor and
// registered globally at #init (below) — the non-intrusive, interface-based registry path
// (the type itself stays untouched).
struct PropAngleEditor {}

impl IPropertyEditor for PropAngleEditor
{
    mtd impl canEdit(type: typeinfo?)->bool => type == PropHeadlessAngle

    mtd impl construct(list: *Properties, value: Swag.TypeValue, data: [*] u8?, parent: *PropertiesItem?)->*PropertiesItem
    {
        g_PropAngleEditorCalls += 1

        let item  = list.addItem(value, data, parent)
        let angle = cast(*PropHeadlessAngle, unwrap data)

        with let ed = EditBox.create(item.line, "", {0, 0, 120, 24})
        {
            // No numeric input mask: the editor shows a "<deg> deg" suffixed string, so the
            // writer parses the leading number out of the free text.
            .sigCommitted += func|list, item, angle|(ed)
            {
                angle.deg = cast(s32, (expect StrConv.toNum's64(ed.text())))
                list.commitItemChange(item)
            }
        }

        item.editBox    = ed
        item.sigRefresh += func|angle|(item) { item.editBox.setText(Format.toString("% deg", angle.deg)) }

        return item
    }
}

#init
{
    Properties.registerEditor'(PropAngleEditor)()
}

// The property editor's options menu keeps its right-aligned trigger inside the popup outline.
func assertPropertyViewMenuAnchor(light: bool)
{
    var host: Testing.HeadlessHost
    host.setup(520, 480)
    if light do
        host.theme.setLight()
    else do
        host.theme.setDark()
    host.notify(.ThemeChanged)

    let panel = Wnd.create'Wnd(&host.root, {36, 40, 440, 280})
    let ctrl  = PropertiesCtrl.create(panel, flags: .SearchBar)
    ctrl.dockStyle = .Center
    host.root.applyLayout()
    host.pump()

    var checked: bool
    host.app.sigFrame += func|host = &host, ctrl, light, checked = &checked|(_)
    {
        if checked[] do
            return
        let popup  = unwrap host.capturedPopupMenu()
        let anchor = ctrl.viewButton.surfaceRect()
        let body   = popup.getPopupBodyRect()
        let origin = popup.surfaceRect()
        Swag.require(popup.popupAnchorButton == ctrl.viewButton)
        Swag.require(popup.popupBarItemSurfaceRect == anchor)
        Swag.require(origin.y + body.y == anchor.bottom() + popup.themeMetrics().menuPopup_AnchorGap)
        Swag.require(origin.x + body.x <= anchor.x)
        Swag.require(origin.x + body.right() >= anchor.right())
        let image = host.render()
        Pixel.Testing.assertImageGolden(&image, light ? "properties.menu.light" : "properties.menu.dark")
        checked[] = true
        popup.setEndModal("property-view-modified-only")
    }

    ctrl.viewButton.sigPressed.call(ctrl.viewButton)
    Swag.require(checked and ctrl.properties.modifiedOnly)
    host.pump()
}

#[Swag.TestTag("golden")]
#test { assertPropertyViewMenuAnchor(false) }

// Every presentation shows checked and unchecked options and a changed mark by a checkbox.
// List also shows a wrapped description and its checkbox at 150% display scale.
func assertPropertyPresentationGolden(kind: PropertiesKind, name: string, light: bool)
{
    var host:   Testing.HeadlessHost
    var height: f32
    switch #complete kind
    {
    case .List:      height = 880
    case .Grid:      height = 620
    case .Panel:     height = 680
    case .Condensed: height = 460
    }

    host.setup(520, height, dpiScale: kind == .List ? 1.5 : 1.0)
    if light
    {
        host.theme.setLight()
        host.notify(.ThemeChanged)
    }

    var data: PropGoldenData
    data.showGuides = false
    data.opacity    = 0.4
    data.caption    = "Main card of the dashboard, in its long version"

    let ctrl = PropertiesCtrl.create(&host.root, kind: kind, flags: .SearchBar)
    ctrl.dockStyle = .Center
    ctrl.properties.setEditorWidth(280)
    if ctrl.properties.isGridLike() do
        ctrl.properties.setNameColumnWidth(150)
    ctrl.addStruct(data, "Inspector")

    host.root.applyLayout()
    host.pump()
    ctrl.properties.setSelItem(findFieldItem(ctrl.properties, #nameof(PropGoldenData.visible)))
    ctrl.properties.focusNavigation()
    let image = host.renderSettled()
    Pixel.Testing.assertImageGolden(&image, Format.toString("%.%", name, light ? "paper" : "ink").toString())
}

#[Swag.TestTag("golden")]
#test { assertPropertyPresentationGolden(.Grid, "properties.grid", false) }
#[Swag.TestTag("golden")]
#test { assertPropertyPresentationGolden(.Condensed, "properties.condensed", true) }
#[Swag.TestTag("golden")]
#test { assertPropertyPresentationGolden(.List, "properties.list", false) }
#[Swag.TestTag("golden")]
#test { assertPropertyPresentationGolden(.Panel, "properties.panel", true) }

// At 150%, the hovered choice reads inline and the focused slider value has room for
// its entire frame. The surrounding controls make any overlap visible.
#[Swag.TestTag("golden")]
#test
{
    var data: PropCondensedEditorData
    data.title = "Capture"
    data.notes = "An editable caption"
    data.values.add(12)

    var host: Testing.HeadlessHost
    host.setup(520, 460, dpiScale: 1.5)
    host.theme.setLight()
    host.notify(.ThemeChanged)

    let prop = Properties.create(&host.root, {12, 12, 496, 436}, .Condensed)
    prop.addStruct(data, "Settings")
    host.root.applyLayout()
    host.pump()

    let level = unwrap findFieldItem(prop, #nameof(PropCondensedEditorData.level))
    prop.setSelItem(level)
    prop.focusNavigation()
    host.keyPress(Input.Key.Return)
    host.app.setFocusVisible(true)
    Swag.require(level.sliderBox.edit.hasVisibleFocus())

    let rate  = unwrap findFieldItem(prop, #nameof(PropCondensedEditorData.rate))
    let combo = rate.comboBox
    host.moveMouse(combo.surfaceRect().center() * combo.deviceScale())
    Swag.require(combo.isHot)

    let image = host.renderSettled()
    Pixel.Testing.assertImageGolden(&image, "properties.condensed.editing.paper")
}

// The section list with its counts, the search and the presentation menu open over the grid,
// in Papier.
func assertPropertiesCtrlGolden(light: bool)
{
    var host: Testing.HeadlessHost
    host.setup(880, 560)
    if light
    {
        host.theme.setLight()
        host.notify(.ThemeChanged)
    }

    var data: PropCtrlGoldenData
    data.opacity = 0.6
    let ctrl = PropertiesCtrl.create(&host.root, kind: .Grid, flags: .SectionNavigation | .SearchBar)
    ctrl.dockStyle = .Center
    ctrl.addStruct(data)
    host.root.applyLayout()
    host.pump()
    ctrl.search.setText("op")
    ctrl.search.setFocus()
    host.settleAnimations(ctrl, 6)

    var checked: bool
    host.app.sigFrame += func|host = &host, light, checked = &checked|(_)
    {
        if checked[] do
            return
        let popup = unwrap host.capturedPopupMenu()
        let image = host.render()
        Pixel.Testing.assertImageGolden(&image, light ? "properties.ctrl.paper" : "properties.ctrl.ink")
        checked[] = true
        popup.setEndModal("property-view-panel")
    }

    ctrl.viewButton.sigPressed.call(ctrl.viewButton)
    Swag.require(checked and ctrl.properties.kind == .Panel)
    host.pump()
}

#[Swag.TestTag("golden")]
#test { assertPropertiesCtrlGolden(true) }
