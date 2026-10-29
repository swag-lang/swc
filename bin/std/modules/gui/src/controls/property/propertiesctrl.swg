#global public

using Core, Pixel

// Configures optional navigation and filtering UI around a property editor.
#[Swag.EnumFlags]
enum PropertiesCtrlFlags
{
    None = 0              // Shows only the property editor.
    SearchBar             // Adds text search and view options at the top.
    SectionNavigation     // Adds a hierarchical section pane on the left.
    SectionTabs           // Adds top tabs that filter by section.
}

// Combines a property editor with optional section navigation, tabs, and search.
struct PropertiesCtrl
{
    public
    {
        using frameWnd: FrameWnd     // Embedded frame behavior and presentation.

        readonly
        {
            late splitter:   *SplitterCtrl     // Splitter holding the section list and the grid.
            late list:       *ListCtrl         // Section list; its pane is hidden without [[Gui.PropertiesCtrlFlags.SectionNavigation]].
            late tab:        *Tab              // Section tabs, when [[Gui.PropertiesCtrlFlags.SectionTabs]] is set.
            late search:     *EditBox          // Search field, when [[Gui.PropertiesCtrlFlags.SearchBar]] is set.
            late viewButton: *IconButton       // View-options button beside [[Gui.PropertiesCtrl.search]].
            late properties: *Properties       // Property editor owned by this control.
        }

        readonly flags: PropertiesCtrlFlags     // Active optional UI features.
    }

    sectionLines: Array'(*ListLine)     // Line of the section list of each section of the editor, in order.
}

// The commands of the presentations of the view menu, in the order of [[Gui.PropertiesKind]].
private const KindCommands = ["property-view-list", "property-view-grid", "property-view-condensed", "property-view-panel"]

impl PropertiesCtrl
{
    // Creates a property editor and its requested navigation controls.
    #[Swag.Discardable]
    func create(parent: *Wnd, position: Math.Rectangle = {}, kind = PropertiesKind.List, flags = PropertiesCtrlFlags.SectionNavigation, id: WndId? = null)->*PropertiesCtrl
    {
        with let ed = Wnd.create'PropertiesCtrl(parent, "", position, id)
        {
            .flags = flags

            .splitter = SplitterCtrl.create(ed, vertical: false)
            .splitter.dockStyle = .Center

            .list = ListCtrl.createSimple(.splitter)
            .list.updateFlags(.ReserveExpandMargin)
            .list.setFirstColumnIconMargin(false)
            .list.sigSelectionChanged += func|ed|(list)
            {
                let sel = list.focusedLine()
                if not sel do
                    return
                list.toggleExpand(sel)
                let item = cast(*PropertiesItem, unwrap sel.userData0)
                let pos  = item.label.rectRelativeTo(ed.properties.edView)
                ed.properties.scrollWnd.setScrollPos(0, pos.y)
            }

            .properties = Properties.create(.splitter, kind: kind)
            .properties.sigValueChanged += func|ed|(_, _) { ed.refreshSectionCounts() }

            .splitter.addPane(.list)
            .splitter.addPane(.properties)

            if not flags.has(.SectionNavigation) do
                .splitter.setPaneVisible(0, false)
        }

        // Filter bar and view options
        if flags.has(.SearchBar)
        {
            with let bar = Wnd.create'Wnd(ed, {0, 0, 0, 36})
            {
                .dockStyle = .Top
                .margin.w  = 8
            }

            with ed.viewButton = IconButton.create(bar, ed.theme().icon(.More, 18), {0, 0, 36, 36})
            {
                .dockStyle  = .Right
                .margin.x   = 8
                .toolTip    = strings().prop_ViewOptions
                .sigPressed += func|ed|(_) { ed.openViewMenu() }
            }

            with ed.search = EditBox.create(bar, "")
            {
                .dockStyle = .Center
                .setIcon(ed.theme().icon(ThemeIcons.Search, 18))
                .setPlaceholder(strings().prop_Search)
                .sigTextChanged += func|ed|(fil) { ed.applySearch(fil.text()) }
                .updateFlags(.ClearButton)
            }
        }

        // Section filter bar
        if flags.has(.SectionTabs)
        {
            with ed.tab = Tab.create(ed, {0, 0, 0, 30})
            {
                .margin.w  = 12
                .dockStyle = .Top
                .setForm(.PushButton)
                .sigSelectionChanged += func|ed|(tab) { ed.properties.setCurrentSection(cast(u32, cast(u64, tab.selectedItem()!.userData0))) }
            }
        }

        ed.applyLayout()
        return ed
    }

    private mtd fillSections()
    {
        .list.clear()
        .sectionLines.clear()

        // In the filter bar
        if .tab != null
        {
            .tab.clear()
            let tabItem = .tab.addItem(strings().prop_All)
            tabItem.userData0 = cast(*void?, .properties.sections.count)
        }

        for &it, idx in .properties.sections
        {
            let item = unwrap it.item
            var naked: String

            // A category header writes its name in capitals; the list names it as declared.
            if item.flags.has(.Category) do
                naked = Properties.resolveText(item.typeValue.name orelse "")
            elif item.label != null do
                naked = RichString.plainText(item.label.text())
            else do
                naked = Properties.resolveText(item.typeValue.name orelse "")

            // In the filter bar
            if .tab != null and it.lvl == 0
            {
                let tabItem = .tab.addItem(naked)
                tabItem.userData0 = cast(*void?, idx)
            }

            // In the left pane, under the section that holds it.
            var parentLine: *ListLine?
            var scan = item.parent
            while scan and not parentLine
            {
                for line in .sectionLines where cast(*PropertiesItem?, line.userData0) == scan
                {
                    parentLine = line
                    break
                }

                scan = scan.parent
            }

            let line = .list.createLine(naked, parentLine: parentLine)
            line.userData0 = it.item
            .sectionLines.add(line)
        }

        // Every section is listed.
        for line in .sectionLines where not line.lines.isEmpty() do
            .list.expand(line)

        .refreshSectionCounts()
    }

    // Writes after each section of the list how many of its fields the filters let through. A
    // section a filter leaves empty fades.
    private mtd refreshSectionCounts()
    {
        let faint     = .themeColors().faintText
        let filtering = .properties.hasActiveFilter()
        var none: Color
        for line, index in .sectionLines
        {
            let count       = .properties.sectionFieldCount(index)
            with let figure = line.setItem(1, Format.toString("%", count))
            {
                .horzAlign = .Right
                .mono      = true
                .colorFg   = faint
            }

            line.items[0]!.colorFg = filtering and count == 0 ? faint : none
        }

        .list.invalidate()
    }

    // Shows the editor in the `kind` presentation, with the same structures and filters.
    mtd setKind(kind: PropertiesKind)
    {
        if .properties.kind == kind do
            return
        .properties.setKind(kind)
        .fillSections()
    }

    // Filters the rows by `text` and writes how many fields it found at the end of the search field.
    private mtd applySearch(text: string)
    {
        .properties.setFilter(text)
        if .properties.stringFilter.isEmpty()
        {
            .search.setReading("")
        }
        else
        {
            let count = .properties.matchCount()
            .search.setReading(Format.toString(count == 1 ? strings().prop_ResultOne : strings().prop_ResultMany, count))
        }

        .refreshSectionCounts()
    }

    private mtd openViewMenu()
    {
        const ExpandAll      = "property-view-expand-all"
        const CollapseAll    = "property-view-collapse-all"
        const ExpandModified = "property-view-expand-modified"
        const ModifiedOnly   = "property-view-modified-only"

        let menu     = MenuCtrl.createPopup(me)
        let gridLike = .properties.isGridLike()

        // The presentations first, the one in force checked.
        let texts = strings()
        let kinds = [texts.prop_KindList, texts.prop_KindGrid, texts.prop_KindCondensed, texts.prop_KindPanel]
        menu.addLabel(texts.prop_Presentation)
        for name, index in kinds do
            menu.addItem(name, KindCommands[index], checked: cast(u64, .properties.kind) == index)
        menu.addSeparator()

        menu.addItem(strings().prop_ExpandAll, ExpandAll, .theme().icon(.ChevronDown), disabled: not gridLike)
        menu.addItem(strings().prop_CollapseAll, CollapseAll, .theme().icon(.ChevronUp), disabled: not gridLike)
        menu.addItem(strings().prop_ExpandModified, ExpandModified, .theme().icon(.Undo), disabled: not gridLike)
        menu.addSeparator()
        menu.addItem(strings().prop_ShowModifiedOnly, ModifiedOnly, .theme().icon(.Filter), checked: .properties.modifiedOnly)

        let sel = menu.doModal(.viewButton, autoDestroy: true)
        switch sel
        {
        case ExpandAll:
            .properties.expandAll()

        case CollapseAll:
            .properties.collapseAll()

        case ExpandModified:
            .properties.expandModified()

        case ModifiedOnly:
            .properties.setModifiedOnly(not .properties.modifiedOnly)
            .refreshSectionCounts()

        default:
            for id, index in KindCommands where sel == id do
                .setKind(cast(PropertiesKind, cast(u32, index)))
        }
    }

    // Appends one reflected structure and rebuilds section navigation.
    mtd addStruct(val: any, section: string? = null)
    {
        .properties.addStruct(val, section)
        .fillSections()
    }

    // Removes every row, along with the section tabs and the section list built from them.
    //
    // The counterpart of [[Gui.PropertiesCtrl.addStruct]]: a caller that adds the same
    // structures again gets a grid rebuilt from scratch, which is what makes a generated
    // panel follow a language switch. The search text and the scroll position are not
    // preserved.
    mtd clear()
    {
        .properties.clear()
        .fillSections()
    }

    // Gives the keyboard focus to the property grid in navigation mode, so the whole control is driven by keyboard.
    mtd focusProperties()
    {
        .properties.focusNavigation()
    }
}
