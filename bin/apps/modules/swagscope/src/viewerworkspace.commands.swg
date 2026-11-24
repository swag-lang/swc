#global internal

using Core, Gui, Pixel

namespace SceneCommands
{
    const CompareSelection = "scope.scene.compareSelection"
    const Beside           = "scope.scene.beside"
    const CompareWith      = "scope.scene.compareWith"
    const OpenGrid         = "scope.scene.openGrid"
    const Compare          = "scope.scene.compare"
    const Maximize         = "scope.scene.maximize"
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

func sceneLayoutIcon(layout: SceneLayout)->ThemeIcons
{
    switch #complete layout
    {
    case .Single:                       return .FitView
    case .SideBySide:                   return .Columns
    case .Stacked:                      return .Rows
    case .Auto, .Grid2, .Grid3, .Grid4: return .Grid
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
        let layoutLabel = func()->string => appStrings().scene_Layout
        .lens.addCommands(layoutLabel, SceneCommands.Layouts[0 until 6], inLens: false)
        .lens.addCommands(func()->string => appStrings().scene_SceneList, [SceneCommands.Layouts[6], SceneCommands.OpenGrid])
        .lens.addCommands(func()->string => appStrings().lens_File, [SceneCommands.Beside, SceneCommands.CompareWith, SceneCommands.CompareSelection])
        .lens.addCommands(func()->string => appStrings().lens_View, [SceneCommands.Compare, SceneCommands.Maximize])
        .lens.addSource(.Action, func|document = me|(results) { document.describeScenes(results, atRest: false) })
        .registerKeyShortcut(.Control, .W, ViewerCommands.Close)
        .registerKeyShortcut(.None, .F, SceneCommands.Maximize)
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
        let scene     = workspace.scene()
        if scene and scene.views.count > 1
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

            if atRest
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
        var icon         = ThemeIcons.SelectAll
        switch evt.id
        {
        case SceneCommands.Beside:
            icon   = .Duplicate
            name   = text.scene_OpenBeside
            hidden = not scene or workspace.vacancy != null or scene.views.count >= ViewerWorkspace.MaxViews

        case SceneCommands.CompareSelection:
            icon   = .Duplicate
            name   = text.scene_Compare
            hidden = not .isExploring() or .explorer!.selectionPaths().count != 2

        case SceneCommands.CompareWith:
            icon     = .Duplicate
            name     = text.scene_CompareWith
            hidden   = not scene or workspace.vacancy != null or .isExploring()
            disabled = scene and scene.views.count > 1 and workspace.scenes.count >= ViewerWorkspace.MaxScenes

        case SceneCommands.OpenGrid:
            icon = .OpenFile
            name = text.scene_OpenGrid

        case SceneCommands.Compare:
            icon      = .Duplicate
            name      = text.scene_Compare
            hidden    = not scene or scene.views.count != 2
            checkable = true
            checked   = scene and scene.compared

        case SceneCommands.Maximize:
            icon   = scene and scene.maximized ? .ExitFullScreen : .FullScreen
            name   = scene and scene.maximized ? text.scene_RestoreLayout : text.scene_Maximize
            hidden = not scene or workspace.vacancy != null or scene.views.count < 2

        default:
            for id, index in SceneCommands.Layouts where id == evt.id
            {
                let layout = SceneCommands.LayoutValues[index]
                icon      = sceneLayoutIcon(layout)
                name      = sceneLayoutTitle(layout)
                hidden    = not scene or scene.views.count < 2
                disabled  = scene and not scene.supportsLayout(layout)
                checkable = true
                checked   = scene and scene.visibleLayout() == layout
                break
            }
        }

        if not name.count do
            return false
        evt.name          = name
        evt.hidden        = hidden
        evt.disabled      = disabled
        evt.icon          = .theme().icon(icon, .themeMetrics().menuPopup_IconSize)
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

        default:
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
