#global public

using Core, Pixel

// Configures optional navigation and filtering UI around a property editor.
#[Swag.EnumFlags]
enum PropertiesCtrlFlags
{
    None = 0              // Shows only the property editor.
    SearchBar             // Adds a text search bar at the top.
    SectionNavigation     // Adds a hierarchical section pane on the left.
    SectionTabs           // Adds top tabs that filter by section.
}

// Combines a property editor with optional section navigation, tabs, and search.
struct PropertiesCtrl
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
        properties: *Properties     // Property editor owned by this control.
    }

    readonly
    flags: PropertiesCtrlFlags     // Active optional UI features.
}

impl PropertiesCtrl
{
    // Creates a property editor and its requested navigation controls.
    #[Swag.Discardable]
    func create(parent: *Wnd, position: Math.Rectangle = {}, kind = PropertiesKind.List, flags = PropertiesCtrlFlags.SectionNavigation, id: #null WndId = null)->*PropertiesCtrl
    {
        Debug.assert(parent)
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
                let item = notnull cast(#null *PropertiesItem) sel.userData0
                let pos  = item.label.rectRelativeTo(ed.properties.edView)
                ed.properties.scrollWnd.setScrollPos(0, pos.y)
            }

            .properties = Properties.create(.splitter, kind: kind)

            .splitter.addPane(.list)
            .splitter.addPane(.properties)

            if !flags.has(.SectionNavigation) do
                .splitter.setPaneVisible(0, false)
        }

        // Filter bar
        if flags.has(.SearchBar)
        {
            with let filter = EditBox.create(ed, "")
            {
                .setIcon(ed.theme().icon24(ThemeIcons24.Search, 18))
                .dockStyle = .Top
                .setPlaceholder("Search")
                .margin.w       = 8
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
                .sigSelectionChanged += func|ed|(tab) { ed.properties.setCurrentSection(cast(u32) cast(u64) (notnull tab.selectedItem()).userData0); }
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
            let tabItem = .tab.addItem("All")
            tabItem.userData0 = cast(#null *void) .properties.sections.count
        }

        var parentLine: #null *ListLine
        for &it, [idx] in .properties.sections
        {
            let str   = (notnull it.item).label.text()
            let naked = RichString.plainText(str)

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

    // Appends one reflected structure and rebuilds section navigation.
    mtd addStruct(val: any, section: #null string = null)
    {
        .properties.addStruct(val, section)
        .fillSections()
    }

    // Give the keyboard focus to the property grid (navigation mode), so the whole
    // control can be driven by keyboard.
    mtd focusProperties()
    {
        .properties.focusNavigation()
    }
}
