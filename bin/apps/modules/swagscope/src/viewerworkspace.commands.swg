#global internal

using Core, Gui, Pixel

namespace TabCommands
{
    const New         = "scope.scene.tab.new"
    const NewGrid     = "scope.scene.tab.newGrid"
    const OpenFile    = "scope.scene.tab.openFile"
    const OpenFolder  = "scope.scene.tab.openFolder"
    const OpenItem    = "scope.scene.tab.openItem"
    const Close       = "scope.scene.tab.close"
    const CloseOthers = "scope.scene.tab.closeOthers"
    const CloseAll    = "scope.scene.tab.closeAll"
}

namespace SceneCommands
{
    const CompareSelection = "scope.scene.compareSelection"
    const Beside           = "scope.scene.beside"
    const CompareWith      = "scope.scene.compareWith"
    const OpenGrid         = "scope.scene.openGrid"
    const Compare          = "scope.scene.compare"
    const Maximize         = "scope.scene.maximize"
    const Equalize         = "scope.scene.equalize"
    const SwapDirections   = ["scope.scene.swapLeft", "scope.scene.swapRight", "scope.scene.swapUp", "scope.scene.swapDown"]
    const ArrowKeys        = [Input.Key.Left, .Right, .Up, .Down]
    const LayoutValues     = [SceneLayout.Single, .SideBySide, .Stacked, .Grid2, .Grid3, .Grid4, .Auto]
    const Layouts          = ["scope.scene.single", "scope.scene.sideBySide", "scope.scene.stacked",
                              "scope.scene.grid2", "scope.scene.grid3", "scope.scene.grid4", "scope.scene.auto"]
}

func sceneLayoutTitle(layout: SceneLayout)->string
{
    let text = appStrings()
    switch #complete layout
    {
    case .Single:     return text.scene_Single
    case .SideBySide: return text.scene_SideBySide
    case .Stacked:    return text.scene_Stacked
    case .Grid2:      return text.scene_Grid2
    case .Grid3:      return text.scene_Grid3
    case .Grid4:      return text.scene_Grid4
    case .Auto:       return text.scene_Auto
    }
}

func sceneGrid(count: u64)->SceneLayout
{
    if count <= 4 do
        return .Grid2
    return count <= 9 ? .Grid3 : .Grid4
}

impl ViewerWindow
{
    mtd addSceneCommands()
    {
        .lens.addCommands(func()->string => appStrings().scene_SceneList,
                          [TabCommands.New, TabCommands.NewGrid, TabCommands.OpenFile, TabCommands.OpenFolder,
                           TabCommands.Close, TabCommands.CloseOthers, TabCommands.CloseAll])
        let layoutLabel = func()->string => appStrings().scene_Layout
        .lens.addCommands(layoutLabel, SceneCommands.Layouts[0 until 6], inLens: false)
        .lens.addCommands(func()->string => appStrings().scene_SceneList, [SceneCommands.Layouts[6], SceneCommands.OpenGrid])
        .lens.addCommands(func()->string => appStrings().lens_File, [SceneCommands.Beside, SceneCommands.CompareWith, SceneCommands.CompareSelection])
        .lens.addCommands(func()->string => appStrings().lens_View, [SceneCommands.Compare, SceneCommands.Maximize, SceneCommands.Equalize])
        .lens.addCommands(func()->string => appStrings().scene_Controls, SceneCommands.SwapDirections)
        for id, index in SceneCommands.SwapDirections do
            .registerKeyShortcut(.CtrlAlt, SceneCommands.ArrowKeys[index], id)
        .lens.addSource(.Action, func|document = me|(results) { document.describeScenes(results, atRest: false) })
        .registerKeyShortcut(.Control, .T, TabCommands.New)
        .registerKeyShortcut(.Control, .W, ViewerCommands.Close)
        .registerKeyShortcut(.None, .F6, SceneCommands.Maximize)
        .registerKeyShortcut(.Control, .Oem5, SceneCommands.Layouts[1])
        .registerKeyShortcut(.CtrlAlt, .D2, SceneCommands.Layouts[3])
        .registerKeyShortcut(.CtrlAlt, .D3, SceneCommands.Layouts[4])
        .registerKeyShortcut(.CtrlAlt, .D4, SceneCommands.Layouts[5])
        .registerKeyShortcut(.CtrlAlt, .D0, SceneCommands.Layouts[6])
        .registerKeyShortcut(.Control, .D, SceneCommands.Compare)
        .addComparisonCommands()
        .addMediaCommands()
    }

    mtd describeScenes(results: *Lens.Results, atRest: bool)
    {
        let workspace = unwrap .workspace
        if workspace.canSetLayout()
        {
            let label   = appStrings().scene_Layout
            var matches = atRest or Lens.match(results.folded, label).matched
            for layout in SceneCommands.LayoutValues[0 until 6] where not matches do
                matches = Lens.match(results.folded, sceneLayoutTitle(layout)).matched
            if matches
            {
                let layouts = results.addSection(label)
                layouts.inline = true
                .lens.addCommandRows(layouts, SceneCommands.Layouts[0 until 6])
            }

            if atRest and workspace.documentCount() > 1
            {
                let actions = results.addSection("")
                .lens.addCommandRows(actions, [SceneCommands.Layouts[6], SceneCommands.OpenGrid, SceneCommands.Maximize, SceneCommands.Compare])
            }
        }

        if workspace.scenes.count < 2 do
            return
        let scenes = results.addSection(appStrings().scene_SceneList)
        for sceneValue, index in workspace.scenes
        {
            let name = workspace.sceneName(unwrap sceneValue)
            if not atRest and not Lens.match(results.folded, name).matched do
                continue
            with let entry = scenes.addEntry(name)
            {
                .checked = index == workspace.active
                .run     = func|workspace, index|() { workspace.selectScene(index) }
            }
        }
    }

    mtd sceneLayoutGlyph(layout: SceneLayout)->Icon
    {
        let size = .themeMetrics().menuPopup_IconSize
        switch #complete layout
        {
        case .Single:     return .scopeIcon(.SingleView)
        case .SideBySide: return .theme().icon(.Columns, size)
        case .Stacked:    return .theme().icon(.Rows, size)
        case .Grid2:      return .theme().icon(.Grid, size)
        case .Grid3:      return .scopeIcon(.GridThree)
        case .Grid4:      return .scopeIcon(.GridFour)
        case .Auto:       return .scopeIcon(.GridAuto)
        }
    }

    mtd computeSceneCommand(evt: *CommandStateEvent)->bool
    {
        let workspace = .workspace
        if not workspace do
            return false
        let scene        = workspace.scene()
        let text         = appStrings()
        var name: string = ""
        var hidden       = false
        var disabled     = false
        var checkable    = false
        var checked      = false
        var icon: Icon
        let size         = .themeMetrics().menuPopup_IconSize
        switch evt.id
        {
        case TabCommands.New, TabCommands.NewGrid, TabCommands.OpenFile, TabCommands.OpenFolder:
            disabled = workspace.scenes.count >= ViewerWorkspace.MaxScenes
            switch evt.id
            {
            case TabCommands.New:
                name = text.tab_New
                icon = .theme().icon(.Plus, size)
            case TabCommands.NewGrid:
                name = text.tab_NewGrid
                icon = .theme().icon(.Grid, size)
            case TabCommands.OpenFile:
                name = text.tab_OpenFile
                icon = .theme().icon(.OpenFile, size)
            case TabCommands.OpenFolder:
                name = text.tab_OpenFolder
                icon = .theme().icon(.Folder, size)
            }

        case TabCommands.Close, TabCommands.CloseOthers, TabCommands.CloseAll:
            hidden = not scene
            switch evt.id
            {
            case TabCommands.Close:
                name = text.tab_Close
                icon = .theme().icon(.WndClose, size)
            case TabCommands.CloseOthers:
                name     = text.tab_CloseOthers
                icon     = .theme().icon(.Remove, size)
                disabled = workspace.scenes.count < 2
            case TabCommands.CloseAll:
                name = text.tab_CloseAll
                icon = .theme().icon(.RemoveAll, size)
            }

        case SceneCommands.Beside:
            icon   = .scopeIcon(.OpenBeside)
            name   = text.scene_OpenBeside
            hidden = not scene or workspace.vacancy != null or scene.views.count >= ViewerWorkspace.MaxViews

        case SceneCommands.CompareSelection:
            icon   = .scopeIcon(.Compare)
            name   = text.scene_Compare
            hidden = not .isExploring() or .explorer!.selectionPaths().count != 2

        case SceneCommands.CompareWith:
            icon     = .scopeIcon(.Compare)
            name     = text.scene_CompareWith
            hidden   = not scene or workspace.vacancy != null or .isExploring()
            disabled = scene and scene.views.count > 1 and workspace.scenes.count >= ViewerWorkspace.MaxScenes

        case SceneCommands.OpenGrid:
            icon = .theme().icon(.Grid, size)
            name = text.scene_OpenGrid

        case SceneCommands.Compare:
            icon      = .scopeIcon(.Compare)
            name      = text.scene_Compare
            hidden    = not scene or scene.views.count != 2
            checkable = true
            checked   = scene and scene.compared

        case SceneCommands.Maximize:
            icon     = .theme().icon(scene and scene.maximized ? ThemeIcons.ExitFullScreen : ThemeIcons.FullScreen, size)
            name   = scene and scene.maximized ? text.scene_RestoreLayout : text.scene_Maximize
            hidden = not scene or workspace.vacancy != null or scene.views.count < 2
            disabled = workspace.focusOnGrid

        case SceneCommands.Equalize:
            name   = text.scene_Equalize
            icon   = .scopeIcon(.EqualCells)
            hidden = not workspace.isTiled() or (scene?.compared orelse false)

        default:
            let swapNames = [text.scene_SwapLeft, text.scene_SwapRight, text.scene_SwapUp, text.scene_SwapDown]
            let swapIcons = [ThemeIcons.ChevronLeft, .ChevronRight, .ChevronUp, .ChevronDown]
            for id, index in SceneCommands.SwapDirections where id == evt.id
            {
                name   = swapNames[index]
                icon   = .theme().icon(swapIcons[index], size)
                hidden = not workspace.isTiled()
                let cell = workspace.neighbourCell(SceneCommands.ArrowKeys[index])
                disabled = workspace.focusOnGrid or
                           cell == Swag.U64.Max or
                           (workspace.vacancy and scene!.viewInCell(cell) == Swag.U64.Max)
                break
            }

            for id, index in SceneCommands.Layouts where id == evt.id
            {
                let layout = SceneCommands.LayoutValues[index]
                icon      = .sceneLayoutGlyph(layout)
                name      = sceneLayoutTitle(layout)
                hidden    = not workspace.canSetLayout()
                disabled  = scene and not scene.supportsLayout(layout)
                checkable = true
                checked   = (scene?.visibleLayout() orelse SceneLayout.Single) == layout
                break
            }
        }

        if not name.count do
            return false
        evt.name          = name
        evt.hidden        = hidden
        evt.disabled      = disabled
        evt.icon          = icon
        evt.updatedFields |= .Name | .Hidden | .Disabled | .Icon
        if checkable
        {
            evt.checked = checked
            evt.updatedFields.add(.Checked)
        }

        evt.accepted = true
        return true
    }

    mtd runSceneCommand(id: WndId)->bool
    {
        let workspace = .workspace
        if not workspace do
            return false
        switch id
        {
        case TabCommands.New:         workspace.newTab()
        case TabCommands.NewGrid:     workspace.newTab(.Grid2)
        case TabCommands.Close:       workspace.closeScene(workspace.active)
        case TabCommands.CloseOthers: workspace.closeTabs(keep: workspace.active)
        case TabCommands.CloseAll:    workspace.closeTabs()

        case TabCommands.OpenFile, TabCommands.OpenFolder:
            if workspace.scenes.count >= ViewerWorkspace.MaxScenes do
                return true
            if id == TabCommands.OpenFile do
                .chooseFile(newTab: true)
            else
            {
                let folder = .selectExplorerFolder()
                if not folder.isEmpty() do
                    workspace.openDocument(folder, newTab: true)
            }

        case SceneCommands.Beside, SceneCommands.CompareWith, SceneCommands.OpenGrid:
            let grid    = id == SceneCommands.OpenGrid
            let compare = id == SceneCommands.CompareWith
            let scene   = workspace.scene()
            if not grid and (not scene or not compare and scene.views.count >= ViewerWorkspace.MaxViews) do
                return true
            with var options: FileDlgOptions
            {
                .state = &workspace.primary.fileDlgState
                .mode  = grid ? .SelectFiles : .SelectFile
                .title = grid ? appStrings().scene_OpenGrid :
                         (id == SceneCommands.Beside ? appStrings().scene_OpenBeside : appStrings().scene_CompareWith)
                .confirmButtonText = appStrings().dlg_ButtonOpen
                .filters.add({name: appStrings().dlg_AllFiles, extensions: ""})
            }

            let dialog = FileDlg.create(unwrap .surface, options)
            if dialog.doModal() != Dialog.BtnOk do
                return true
            if grid
            {
                let selected = dialog.selectedPaths()
                workspace.openScene(selected.toSlice(), sceneGrid(selected.count))
            }
            elif compare and scene!.views.count > 1
            {
                workspace.openScene([scene!.views[scene.active].path, dialog.selectedPath()], .SideBySide, compare: true)
            }
            else
            {
                workspace.openBeside(dialog.selectedPath())
                if compare do
                    workspace.toggleComparison()
            }

        case SceneCommands.CompareSelection:
            .explorer?.openSelection(compare: true)

        case SceneCommands.Compare:
            workspace.toggleComparison()

        case SceneCommands.Maximize:
            workspace.toggleMaximized()

        case SceneCommands.Equalize:
            let scene = workspace.scene()
            if scene and workspace.isTiled() and not scene.compared
            {
                let grid = scene.dimensions()
                if grid.x == 1 or grid.y == 1
                {
                    scene.split = 0.5
                }
                else
                {
                    scene.columnCuts.clear(cast(u64, grid.x))
                    scene.rowCuts.clear(cast(u64, grid.y))
                }

                workspace.layoutScene()
                catch workspace.primary.saveState()
            }

        default:
            for item, index in SceneCommands.SwapDirections where item == id do
                return workspace.moveView(SceneCommands.ArrowKeys[index], swap: true)

            for item, index in SceneCommands.Layouts where item == id
            {
                workspace.setLayout(SceneCommands.LayoutValues[index])
                return true
            }

            return false
        }

        return true
    }
}
