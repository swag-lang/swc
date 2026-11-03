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
        Swag.assert(popup.popupAnchorButton == ctrl.viewButton)
        Swag.assert(popup.popupBarItemSurfaceRect == anchor)
        Swag.assert(origin.y + body.y == anchor.bottom())
        Swag.assert(origin.x + body.x <= anchor.x)
        Swag.assert(origin.x + body.right() >= anchor.right())
        let image = host.render()
        Pixel.Testing.assertImageGolden(&image, light ? "properties.menu.light" : "properties.menu.dark")
        checked[] = true
        popup.setEndModal("property-view-modified-only")
    }

    ctrl.viewButton.sigPressed.call(ctrl.viewButton)
    Swag.assert(checked and ctrl.properties.modifiedOnly)
    host.pump()
}

#[Swag.TestTag("golden")]
#test { assertPropertyViewMenuAnchor(false) }

// Each presentation is a separate rendering contract. In particular, Condensed owns a flat,
// edge-to-edge editor layout and must not silently inherit the normal grid's spacing or chrome.
func assertPropertyPresentationGolden(kind: PropertiesKind, name: string, light: bool)
{
    var host: Testing.HeadlessHost
    host.setup(520, 620)
    if light
    {
        host.theme.setLight()
        host.notify(.ThemeChanged)
    }

    var data: PropGoldenData
    data.opacity = 0.4
    data.caption = "Main card of the dashboard, in its long version"

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
    host.settleAnimations(ctrl, 6)

    let image = host.render()
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
    Swag.assert(checked and ctrl.properties.kind == .Panel)
    host.pump()
}

#[Swag.TestTag("golden")]
#test { assertPropertiesCtrlGolden(true) }
