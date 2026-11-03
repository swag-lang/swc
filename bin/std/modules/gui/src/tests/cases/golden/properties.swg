#global if #command == Swag.CompilerCommand.Test
#global internal

using Swag, Core

struct PropHeadlessData
{
    count:   s32     = 42
    label:   string? = "hello"
    enabled: bool    = true
}

struct PropHeadlessHiddenData
{
    visible: s32 = 1

    #[Properties.Hidden]
    persistedOnly: s32 = 2
}

struct PropHeadlessCustomData
{
    origin: Math.Point = {10, 20}
    count:  s32        = 3
}

enum PropHeadlessChoice
{
    Low
    Mid
    High
}

struct PropHeadlessEnumData
{
    choice: PropHeadlessChoice = .Mid
}

// Carries one of each presentation attribute a text resolver has to reach.
struct PropHeadlessResolvedData
{
    #[Category("Numbers"), Name("Count")]
    count: s32 = 42

    #[Name("Line"), BoolCombo("Straight", "Bezier")]
    bezier: bool
}

struct PropHeadlessSliderData
{
    #[SliderMinMax(0, 100)]
    volume: s32 = 50

    #[SliderMinMax(0, 10)]
    level: s32 = 5
}

struct PropHeadlessFontData
{
    #[Properties.FontName]
    face: String
}

// The separator after the default face is not an entry in the system font table.

struct PropHeadlessGroupedData
{
    #[Category("Numbers")]
    count: s32 = 42

    label: string? = "hello"

    #[Category("Flags")]
    enabled: bool = true
}

struct PropHeadlessRoData
{
    normal: s32 = 1

    #[Properties.ReadOnly]
    locked: s32 = 2

    dynamic: s32 = 3
}

struct PropMoveElem
{
    id: s32 = 0
}

struct PropMoveData
{
    dyn:  Array'PropMoveElem
    stat: [3] s32
}

var g_PropRoDynamic: bool

impl IPropertyNotify for PropHeadlessRoData
{
    mtd impl isItemReadOnly(_: *Properties, item: *PropertiesItem)->bool
    {
        if item.typeValue.name == #nameof(PropHeadlessRoData.dynamic) do
            return g_PropRoDynamic
        return false
    }
}

// Properties.addStruct reflects a struct into one item per field (+ a section item).

// Public configuration methods keep their observable state synchronized, and clear makes the
// control reusable without retaining rows or selection state.

// A field kept for persistence can opt out of a generated editor without leaving its structure.

// PropertiesCtrl keeps visible grid rows after the same staged layout sequence
// used by the gui4 example: create at a placeholder height, add structs, then
// dock into its final parent.

// Keyboard navigation: focusNavigation selects the first navigable row, arrows move the
// highlight over the editable rows (clamped), Home/End jump to the ends.

// Enter starts editing the selected row (focuses its editor); Escape returns to
// navigation mode (focus back on the grid).

struct PropHeadlessCancelData
{
    value: s32 = 42
    text:  String

    #[Properties.SliderMinMax(0, 100)]
    bounded: s32 = 10
}

// Cancelling pending text preserves the bound values and creates no change notification or undo.

// While editing, Up/Down auto-commit and move the selection back to navigation
// mode on the adjacent row.

// Tab commits the current edit and starts editing the next editable row.

struct PropHeadlessActionData
{
    #[Description("Visible actions are listed in the preview footer.")]
    visible: bool = true
}

struct PropHeadlessArrayData
{
    origin:  Math.Point = {36, 46}
    actions: Array'PropHeadlessActionData
}

// In list mode each row is a vertical StackLayoutCtrl: the name label on top and the
// value editor stacked underneath. Editors that wrap their control in an inner line
// (bool, vector, array count) must not dock-center that line vertically, or it would
// overlap the name label. This asserts every value child sits fully below its label.

struct PropHeadlessColorData
{
    f0, f1, f2, f3, f4, f5, f6, f7: s32
    tint: Pixel.Color
    f8, f9, f10, f11, f12, f13:     s32
}

// While an editor popup (e.g. the color picker) is open the grid is modal: mouse wheel
// events over the list are swallowed so it cannot scroll out from under the anchored
// popup. Clearing the popup restores scrolling.

func findIconButton(w: *Wnd)->*IconButton?
{
    for c in w.children
    {
        if c is IconButton as button do
            return button
        let sub = findIconButton(c)
        if sub do
            return sub
    }

    return null
}

// The modal block must swallow only wheel events, not hover/leave: otherwise the popup
// trigger button never receives its MouseLeave and stays stuck in the hot state after
// the popup closes. A MouseLeave while the popup is open must still clear the button.

// In navigation mode, Space toggles a bool row's checkbox in place.

// Navigating a slider row: Right steps the slider track and focuses it (auto-commit
// model), a further Right keeps stepping, Down commits and moves to the next row.

// Enter on a slider row edits its value box like a plain editbox row: it focuses the
// inner EditBox and selects its text so the value can be typed over right away.

// Editing an enum row: Enter focuses the combo, Left/Right change the selection
// (reaching the combo, not intercepted) and write back to the data.

// A row with a custom/composite editor (e.g. a Math.Point) is navigable and can be
// activated: Enter focuses the first inner editor, Down auto-commits to the next row.

// focusNavigation keeps the already-selected row (so clicking a header/custom row does not
// jump the selection to the first item).

// A named section becomes the first item and is registered.

// PropertiesCtrl grid keeps deterministic line and editor heights.

// Properties list keeps rows visible after being docked with a filter bar, as
// used by the second page of gui4.

//
// Multi-selection editing: the grid edits several instances of the same struct at once.
//

enum MultiChoice
{
    Low
    Mid
    High
}

#[Swag.EnumFlags]
enum MultiBadges
{
    #[Description("Adds a star marker.")]
    Star

    #[Description("Locks the tile.")]
    Lock

    #[Description("Pins the tile.")]
    Pin
}

struct MultiTile
{
    count:  s32         = 0
    flag:   bool        = false
    name:   String
    choice: MultiChoice = .Low
    badges: MultiBadges
    tint:   Pixel.Color
    pos:    Math.Point  = {0, 0}
}

func findFieldItem(prop: *Properties, name: string)->*PropertiesItem?
{
    for it in prop.items
    {
        let item = unwrap it
        if item.typeValue.name == name do
            return item
    }

    return null
}

// Condensed enum-flag rows keep the marker and its wording in two adjacent cells. The checkbox
// must not take the Center dock used by full-cell editors, which would overlap the label.

// Edits applied through the grid write into every selected instance.

// A field that differs across instances is "mixed": the editor shows no concrete value,
// and editing it resolves the field on every instance.

// A single instance behaves exactly like the classic addStruct (no multi state).

func collectEditBoxes(w: *Wnd, out: *Array'(*EditBox?))
{
    for c in w.children
    {
        if c is EditBox as edit do
            out.add(edit)
        collectEditBoxes(c, out)
    }
}

// Editing one vector component writes that component into every instance while leaving
// the other components (which may legitimately differ) untouched.

// Enum-flags multi-edit logic: a bit that disagrees across instances is "mixed", and
// setting one flag bit on every instance preserves the other (differing) bits. Exercised
// through the helpers directly because the EnumFlags attribute is not reflected in a
// test-mode build, so the flag rows would not be constructed here (they are in gui4).

// Dynamic strings are compared and propagated by content (they own a heap buffer).

// A color (struct via the built-in ColorEditor) reports mixed and propagates as a whole value.

//
// Per-item validation (info / warning / error) state.
//

struct ValData
{
    name:  String
    count: s32 = 5
}

impl Gui.IPropertyNotify for ValData
{
    mtd impl validateItem(_: *Gui.Properties, item: *Gui.PropertiesItem)->Gui.PropValidationResult
    {
        switch item.typeValue.crc
        {
        case Reflection.fieldCrc(ValData, #nameof(ValData.name)):
            if .name.isEmpty() do
                return {.Error, "Name is required."}

        case Reflection.fieldCrc(ValData, #nameof(ValData.count)):
            if .count > 100 do
                return {.Warning, "Count is unusually large."}
        }

        return {}
    }
}

// Validation is computed from the bound struct on build and after each change.

// A validation set manually (no notify interface) is kept across refreshes.

// Read-only fields gray (disable) their editor, while staying visible. Covers both the
// ReadOnly attribute and the dynamic isItemReadOnly notify API, including toggling at runtime.

// Reordering array elements (static + dynamic) and removing a dynamic element by the correct
// index, including struct arrays whose element rows are interleaved with their field rows.

// The context-menu commands run through the shared gui action system (ActionProperties /
// IActionUI): update() computes each item's enabled state, execute() performs the change via a
// real CommandEvent — no hardcoded result-string switch.

// --- Custom editor registry -------------------------------------------------

struct PropHeadlessAngle
{
    deg: s32 = 45
}

struct PropHeadlessAngleData
{
    rot:  PropHeadlessAngle
    name: string? = "x"
}

var g_PropAngleEditorCalls: s32

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

// A registered IPropertyEditor that claims a type overrides the built-in dispatch: the struct
// is not expanded into its sub-fields, the editor's construct runs once per field of that type,
// and its item.sigRefresh drives the displayed value.

// --- Reset to default -------------------------------------------------------

struct PropDefaultData
{
    count:   s32     = 42
    name:    string? = "hello"     // static string: read-only, never resettable
    enabled: bool    = true
}

var g_PropDefResetCalls:    s32
var g_PropDefForceModified: bool

struct PropDefaultCustom
{
    val: s32 = 5
}

impl IPropertyNotify for PropDefaultCustom
{
    // Force the modified state regardless of the actual value (the customizable test).
    mtd impl isItemAtDefault(_: *Properties, item: *PropertiesItem)->PropDefaultState
    {
        if item.typeValue.name == #nameof(PropDefaultCustom.val) do
            return g_PropDefForceModified ? .Modified : .AtDefault
        return .Auto
    }

    // Take over the reset itself.
    mtd impl resetItemToDefault(_: *Properties, item: *PropertiesItem)->bool
    {
        if item.typeValue.name == #nameof(PropDefaultCustom.val)
        {
            g_PropDefResetCalls += 1
            return true
        }

        return false
    }
}

// Built-in detection: a field equal to its declared default is not modified; editing it flags the
// row (isModified + a visible revert button) and Properties.resetItemDefault restores the value.

// The "Reset to default" context-menu command goes through the shared action system: update()
// disables it while the value is at its default and enables it once modified; execute() resets.

// The test and the reset are both customizable through IPropertyNotify: isItemAtDefault forces the
// modified state (even though the value equals the default), and resetItemToDefault handles reset.

// Grid mode: the revert column is reserved on the right of every resettable row (docked, present
// even while at default), so the value editor keeps a constant width; toggling the arrow on/off
// never resizes it. Mirrors the Godot/Unreal revert column.

// Condensed grid mode: the revert button is sized to the condensed editor height, then docked
// right; this keeps it vertically centered in the thin row instead of overflowing from the top.

// Multi-selection: a field is "modified" when it differs from the default in ANY edited instance,
// and reset writes the declared default into every instance.

// Undo/redo of a scalar field edit: each commit records one step; undo/redo walk the timeline;
// canUndo/canRedo track the edges; a no-op change records nothing; a new edit after undo drops
// the redo tail.

// Undo/redo of a dynamic String field (copied by content, not by raw bytes).

// Undo/redo across a multi-selection edit restores every edited instance.

// Ctrl+Z / Ctrl+Y (and Ctrl+Shift+Z) drive undo/redo while the grid is in navigation mode.

// --- Nested subgroups (#3) and decorators (#5) ------------------------------

struct PropDecorData
{
    #[Category("Transform")]
    px: s32 = 1

    #[Category("Transform/Advanced")]
    shear: s32 = 2

    #[Category("Physics")]
    #[Heading("Body")]
    #[Gap(16)]
    #[HelpBox("Affects simulation")]
    mass: s32 = 3
}

// A "/"-separated Category opens nested subgroups (the shared prefix is reused across siblings),
// and the Heading / Gap / HelpBox decorators inject header / spacer / note rows above the field.

struct PropHeadlessFontStyleData
{
    style = Pixel.FontFamilyStyle.Regular
}

struct PropHeadlessPanelStringData
{
    #[Properties.Name("Dynamic text")]
    dynamic: String

    #[Properties.Name("Fixed text")]
    fixed: string = "Read only"
}

// Panel string fields keep a persistent, aligned label. A placeholder stops naming a field as
// soon as it contains a value, and the static-string variant must not fall back to a stacked row.

// The FontFamilyStyle editor is one row of four segments, each lettered "Aa" in the style it
// stands for; choosing one writes that style, and the row follows the field.

struct PropHeadlessUsingBase
{
    baseVal: s32
}

struct PropHeadlessUsingDerived
{
    using base: PropHeadlessUsingBase
    ownVal:     s32
}

// usingFieldsLast walks the struct's own fields before recursing into its 'using'
// bases, so a derived type edits its most specific fields first.

enum PropFilterChoice
{
    Hidden
    Low
    Medium
    High
}

struct PropFilterData
{
    choice = PropFilterChoice.Medium
}

struct PropFilterHost {}

impl IPropertyNotify for PropFilterHost
{
    mtd impl isEnumValueVisible(_: *Properties, _: *PropertiesItem, enumValue: Swag.TypeValue)->bool => enumValue.name != "Hidden"
}

// The host notify can hide enum values (isEnumValueVisible): the combo omits them and
// the selection/write-back mapping stays correct through the remaining entries.

// A String field naming a document, and one holding free text beside it.
struct PropDropData
{
    #[Properties.Name("Source"), Properties.FilePath]
    source: String

    #[Properties.Name("Note")]
    note: String
}

// A file dropped on a FilePath field fills it, and commits with the focus like a typed value.

struct PropSameCategData
{
    #[Properties.Category("Debug"), Properties.Name("First"), Properties.Description("A long description that should wrap over the full control width, not over the value column")]
    first: bool
    #[Properties.Category("Debug"), Properties.Name("Second")]
    second: bool
    #[Properties.Category("Debug"), Properties.Name("Third")]
    third: bool
}

// Consecutive fields sharing the same Category reuse the open header instead of
// creating new segments (regression: the empty 'until' range used to panic).

enum PropAlignChoice { A, B, C }

struct PropAlignData
{
    #[Properties.Name("Slide"), Properties.SliderMinMax(0, 100)]
    slide: f32 = 10
    #[Properties.Name("Choice")]
    choice = PropAlignChoice.A
    #[Properties.Name("Count")]
    count: s32 = 5
}

// List mode: every value editor (slider, combo, edit box) shares the same fixed edit
// width, so their right edges line up — and stay lined up after the control is resized
// (regression: anchored widths drifted with the resize history).

// A field the resolver claims shows its answer; a field it declines keeps the declared
// wording, and the module's own strings answer after it.

// Every generated row goes through the resolver: the field label, the category header,
// and the two entries of a boolean combo.

// Filtering is stronger than the persisted disclosure state: a match remains reachable through
// a collapsed branch, and clearing the query restores that branch to its previous state.

// A search counts the fields it found by their own words, and finds where in the name to mark.

// The modified-only view composes with default tracking and updates immediately when an edit is
// reset. expandModified opens only the path that contains the changed field.

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

enum PropGoldenChoice
{
    Automatic
    Manual
    Disabled
}

struct PropGoldenData
{
    #[Category("Appearance"), Name("Visible"), Description("Shows the element in the composed scene.")]
    visible: bool = true

    #[Category("Appearance"), Name("Opacity"), SliderMinMax(0, 1)]
    opacity: f32 = 0.75

    #[Category("Appearance"), Name("Tint")]
    tint: Pixel.Color = 0xFF38BDF8

    #[Category("Layout"), Name("Offset")]
    offset: Math.Point = {12, 8}

    #[Category("Layout"), Name("Mode"), Properties.ReadOnly]
    mode = PropGoldenChoice.Automatic

    #[Category("Text"), Name("Caption"), HelpBox("Changes apply to the next shapes drawn too.")]
    caption: String
}

impl Gui.IPropertyNotify for PropGoldenData
{
    mtd impl validateItem(_: *Gui.Properties, item: *Gui.PropertiesItem)->Gui.PropValidationResult
    {
        if item.typeValue.crc == Reflection.fieldCrc(PropGoldenData, #nameof(PropGoldenData.caption)) and .caption.length > 40 do
            return {.Warning, "Over 40 characters: the caption will be cut."}
        return {}
    }
}

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

// The settings of a drawn shape, in sections and subsections, for the property editor at its
// fullest: the section list, the search, and the presentation menu.
struct PropCtrlGoldenData
{
    #[Category("Appearance"), Name("Opacity"), SliderMinMax(0, 1)]
    opacity: f32 = 1

    #[Category("Appearance"), Name("Outline Opacity"), SliderMinMax(0, 1)]
    outlineOpacity: f32 = 1

    #[Category("Layout"), Name("Width")]
    width: f32 = 320

    #[Category("Layout"), Name("Height")]
    height: f32 = 200

    #[Category("Text"), Name("Font Size")]
    fontSize: f32 = 14

    #[Category("Advanced/Rendering"), Name("Optimize Gradients")]
    optimizeGradients = true

    #[Category("Advanced/Export"), Name("Scale")]
    scale: f32 = 2
}

// Returns the count the section list writes after the section `index`.
func sectionCountText(ctrl: *PropertiesCtrl, index: u64)->string => ctrl.sectionLines[index].items[1]!.name.raw

// The editor changes presentation at run time: the rows are built again from the same
// structure, with its values and the search in force, and the section list counts the fields
// each section lets through.

// The same section icon also survives a tabbed grid's presentation changes.

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

// The marks of a row in each presentation: a slider reads its value as a figure with no box
// until it is edited, a Condensed warning is a stroke in the margin that says its words on
// hover, and a changed field of a panel names itself with its own control.
