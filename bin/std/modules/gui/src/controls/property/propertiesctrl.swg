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
        using frameWnd: FrameWnd     // Embedded frame wnd state.

        readonly
        {
            #[Swag.Late]
            splitter: *SplitterCtrl     // Splitter associated with this value.
            #[Swag.Late]
            list: *ListCtrl     // List associated with this value.
            #[Swag.Late]
            tab: *Tab     // Tab associated with this value.
            #[Swag.Late]
            search: *EditBox     // Search field, when [[Gui.PropertiesCtrlFlags.SearchBar]] is set.
            #[Swag.Late]
            viewButton: *IconButton     // View-options button beside [[Gui.PropertiesCtrl.search]].
            #[Swag.Late]
            properties: *Properties     // Property editor owned by this control.
        }

        readonly
        flags: PropertiesCtrlFlags     // Active optional UI features.
    }
}

impl PropertiesCtrl
{
    // Creates a property editor and its requested navigation controls.
    #[Swag.Discardable]
    func create(parent: *Wnd, position: Math.Rectangle = {}, kind = PropertiesKind.List, flags = PropertiesCtrlFlags.SectionNavigation, id: #null WndId = null)->*PropertiesCtrl
    {
        let ed = Wnd.create'PropertiesCtrl(parent, "", position, id)

        with ed
        {
            .flags = flags

            .splitter           = SplitterCtrl.create(ed, vertical: false)
            .splitter.dockStyle = .Center

            .list = ListCtrl.createSimple(.splitter)
            .list.updateFlags(.ReserveExpandMargin)
            .list.sigSelectionChanged += func|ed|(list)
            {
                let sel = list.focusedLine()
                if !sel do
                    return
                list.toggleExpand(sel)
                let item = cast(*PropertiesItem) sel.userData0!
                let pos  = item.label.rectRelativeTo(ed.properties.edView)
                ed.properties.scrollWnd.setScrollPos(0, pos.y)
            }

            .properties = Properties.create(.splitter, kind: kind)

            .splitter.addPane(.list)
            .splitter.addPane(.properties)

            if !flags.has(.SectionNavigation) do
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
                .sigPressed += func|ed|(btn) { ed.openViewMenu(btn); }
            }

            with ed.search = EditBox.create(bar, "")
            {
                .dockStyle = .Center
                .setIcon(ed.theme().icon(ThemeIcons.Search, 18))
                .setPlaceholder(strings().prop_Search)
                .sigTextChanged += func|ed|(fil) { ed.properties.setFilter(fil.text()); }
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
                .sigSelectionChanged += func|ed|(tab) { ed.properties.setCurrentSection(cast(u32) cast(u64) tab.selectedItem()!.userData0); }
            }
        }

        ed.applyLayout()
        return ed
    }

    private mtd fillSections()
    {
        .list.clear()

        // In the filter bar
        if @isset(.tab)
        {
            .tab.clear()
            let tabItem = .tab.addItem(strings().prop_All)
            tabItem.userData0 = cast(#null *void) .properties.sections.count
        }

        var parentLine: #null *ListLine
        for &it, idx in .properties.sections
        {
            let item = it.item!
            var naked: String
            if @isset(item.label) do
                naked = RichString.plainText(item.label.text())
            else do
                naked = Properties.resolveText(item.typeValue.name orelse "")

            // In the filter bar
            if @isset(.tab) and it.lvl == 0
            {
                let tabItem = .tab.addItem(naked)
                tabItem.userData0 = cast(#null *void) idx
            }

            // In the left pane
            if it.lvl == 0 do
                parentLine = null

            let line = .list.createLine(naked, parentLine: parentLine)
            line.userData0 = it.item

            if it.lvl == 0 do
                parentLine = line
        }
    }

    private mtd openViewMenu(button: *Button)
    {
        const ExpandAll      = "property-view-expand-all"
        const CollapseAll    = "property-view-collapse-all"
        const ExpandModified = "property-view-expand-modified"
        const ModifiedOnly   = "property-view-modified-only"

        let menu     = MenuCtrl.createPopup(me)
        let gridLike = .properties.isGridLike()
        menu.addItem(strings().prop_ExpandAll, ExpandAll, .theme().icon(.ChevronDown), disabled: !gridLike)
        menu.addItem(strings().prop_CollapseAll, CollapseAll, .theme().icon(.ChevronUp), disabled: !gridLike)
        menu.addItem(strings().prop_ExpandModified, ExpandModified, .theme().icon(.Undo), disabled: !gridLike)
        menu.addSeparator()
        menu.addItem(strings().prop_ShowModifiedOnly, ModifiedOnly, .theme().icon(.Filter), checked: .properties.modifiedOnly)

        let rect = button.surfaceRect()
        let sel  = menu.doModal({rect.x, rect.bottom()}, .TopLeft, autoDestroy: true)
        switch sel
        {
        case ExpandAll:      .properties.expandAll()
        case CollapseAll:    .properties.collapseAll()
        case ExpandModified: .properties.expandModified()
        case ModifiedOnly:   .properties.setModifiedOnly(!.properties.modifiedOnly)
        }
    }

    // Appends one reflected structure and rebuilds section navigation.
    mtd addStruct(val: any, section: #null string = null)
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

    // Give the keyboard focus to the property grid (navigation mode), so the whole
    // control can be driven by keyboard.
    mtd focusProperties()
    {
        .properties.focusNavigation()
    }
}
