#global public

using Core, Core.Errors

// Visible strings of the GUI module.
//
// The declared values are the reference English wording, and each field is one
// translatable key. A language file overrides fields by name, so a file that omits a
// key keeps the reference value and a translation only carries what it changes. Read
// the active table through [[strings]]; never keep a copy across a language switch.
struct Strings
{
    public
    {
        dlg_Ok:            string = "OK"                                      // Confirmation button of a dialog.
        dlg_Cancel:        string = "Cancel"                                  // Cancel button of a dialog.
        dlg_Yes:           string = "Yes"                                     // Positive answer button.
        dlg_No:            string = "No"                                      // Negative answer button.
        dlg_Close:         string = "Close"                                   // Close button of an informational dialog.
        dlg_ConfirmTitle:  string = "Please confirm"                          // Title of a confirmation dialog.
        dlg_ConfirmText:   string = "Do you want to continue?"                // Default question of a confirmation dialog.
        dlg_ErrorTitle:    string = "Error"                                   // Title of an error dialog.
        dlg_InfoTitle:     string = "Information"                             // Title of an informational dialog.
        dlg_MultiLineHint: string = "Press Shift+Enter to add a new line"     // Keyboard hint above a multi-line dialog editor.

        appearance_ToolTip:        string = "Theme and language"     // Tooltip of the application appearance caption button.
        appearance_Theme:          string = "Theme"                  // Theme submenu label.
        appearance_Language:       string = "Language"               // Language submenu label.
        appearance_SystemLanguage: string = "System language"        // Language choice following the user account.
        appearance_Dark:           string = "Dark"                   // Dark application theme.
        appearance_Light:          string = "Light"                  // Light application theme.

        fileDlg_TitleSaveFile:     string = "Save File"                                   // File dialog title when saving a file.
        fileDlg_TitleSelectFile:   string = "Select File"                                 // File dialog title when picking one file.
        fileDlg_TitleSelectFiles:  string = "Select Files"                                // File dialog title when picking several files.
        fileDlg_TitleSelectFolder: string = "Select Folder"                               // File dialog title when picking a folder.
        fileDlg_NewFolderTitle:    string = "New Folder"                                  // Title of the folder-creation dialog.
        fileDlg_NewFolderField:    string = "FOLDER NAME"                                 // Label of the folder-name field.
        fileDlg_NewFolderDefault:  string = "New Folder"                                  // Proposed name of a created folder.
        fileDlg_NewFolderHint:     string = "Folder name"                                 // Placeholder of the folder-name field.
        fileDlg_ErrFolderName:     string = "The folder name is not valid."               // Rejected folder name.
        fileDlg_ErrFolderExists:   string = "A folder with this name already exists."     // Name collision when creating a folder.
        fileDlg_ErrFolderCreate:   string = "The folder could not be created."            // Filesystem refusal when creating a folder.
        fileDlg_ReplaceTitle:      string = "This file already exists."                   // Title of the overwrite confirmation.
        fileDlg_ReplaceText:       string = "Do you want to replace it?"                  // Body of the overwrite confirmation.
        fileDlg_BtnSave:           string = "Save"                                        // Confirmation button when saving a file.
        fileDlg_BtnOpen:           string = "Open"                                        // Confirmation button when opening a file.

        browser_Shortcuts:      string = "Shortcuts"                                   // Locations pane group of user shortcuts.
        browser_Drives:         string = "Drives"                                      // Locations pane group of mounted drives.
        browser_Desktop:        string = "Desktop"                                     // Default shortcut to the desktop.
        browser_Documents:      string = "Documents"                                   // Default shortcut to the documents folder.
        browser_Pictures:       string = "Pictures"                                    // Default shortcut to the pictures folder.
        browser_ColName:        string = "Name"                                        // File list column of entry names.
        browser_ColModified:    string = "Modified"                                    // File list column of last write times.
        browser_ColSize:        string = "Size"                                        // File list column of file sizes.
        browser_AllFiles:       string = "All Files"                                   // Filter matching every extension.
        browser_NewFolder:      string = "New Folder"                                  // Create a folder in the current location.
        browser_TipBack:        string = "Previous folder (Alt+Left)"                  // Tooltip of the back navigation button.
        browser_TipForward:     string = "Next folder (Alt+Right)"                     // Tooltip of the forward navigation button.
        browser_TipRecent:      string = "Recent folders"                              // Tooltip of the recent-folders button.
        browser_TipUp:          string = "Parent folder (Alt+Up)"                      // Tooltip of the parent-folder button.
        browser_TipRefresh:     string = "Refresh (F5)"                                // Tooltip of the refresh button.
        browser_TipNewFolder:   string = "Create a folder in the current location"     // Tooltip of [[browser_NewFolder]].
        browser_FolderName:     string = "Folder Name"                                 // Name field label when picking a folder.
        browser_FileName:       string = "File Name"                                   // Name field label when picking a file.
        browser_Folders:        string = "Folders"                                     // Type filter entry when picking a folder.
        browser_Type:           string = "Type"                                        // Label of the type filter field.
        browser_StatusEmpty:    string = "Empty folder"                                // Status line of a folder with nothing to show.
        browser_StatusFolder:   string = "folder"                                      // Status word for one folder.
        browser_StatusFolders:  string = "folders"                                     // Status word for several folders.
        browser_StatusFile:     string = "file"                                        // Status word for one file.
        browser_StatusFiles:    string = "files"                                       // Status word for several files.
        browser_StatusSelected: string = "  —  % selected"                             // Status suffix with the selection count.

        markdown_AlertNote:      string = "Note"                                                                     // Title of a Markdown [!NOTE] alert.
        markdown_AlertTip:       string = "Tip"                                                                      // Title of a Markdown [!TIP] alert.
        markdown_AlertImportant: string = "Important"                                                                // Title of a Markdown [!IMPORTANT] alert.
        markdown_AlertWarning:   string = "Warning"                                                                  // Title of a Markdown [!WARNING] alert.
        markdown_AlertCaution:   string = "Caution"                                                                  // Title of a Markdown [!CAUTION] alert.
        markdown_EmptyDocument:  string = "This Markdown document is empty."                                         // Placeholder paragraph of an empty document.
        markdown_LoadFailed:     string = "Unable to read this Markdown document."                                   // Document body shown when loading stops.
        markdown_ReadFailed:     string = "Markdown source could not be read"                                        // Fallback load-failure reason.
        markdown_NotUtf8:        string = "Markdown source contains a zero byte and is not supported UTF-8 text"     // Load-failure reason for binary input.

        // Context-menu vocabulary shared by every text-bearing view: editors, the HTML and PDF
        // viewers, and any control offering its selection to the clipboard.
        edit_Cut:       string = "Cut"            // Move the selection to the clipboard.
        edit_Copy:      string = "Copy"           // Copy the selection to the clipboard.
        edit_Paste:     string = "Paste"          // Insert the clipboard at the caret.
        edit_SelectAll: string = "Select All"     // Extend the selection to the whole content.

        prop_Copy:             string = "Copy"                              // Copy the value of a property.
        prop_Paste:            string = "Paste"                             // Paste into a property.
        prop_ResetDefault:     string = "Reset to default"                  // Restore the default value of a property.
        prop_MoveUp:           string = "Move Up"                           // Move a list element up.
        prop_MoveDown:         string = "Move Down"                         // Move a list element down.
        prop_Remove:           string = "Remove"                            // Remove a list element.
        prop_RemoveAll:        string = "Remove All"                        // Remove every list element.
        prop_ConfirmRemove:    string = "This will remove the element"      // Confirmation before removing one element.
        prop_ConfirmRemoveAll: string = "This will remove all elements"     // Confirmation before clearing a list.
        prop_Search:           string = "Search"                            // Placeholder of the property search box.
        prop_All:              string = "All"                               // Tab showing every category.
        prop_ViewOptions:      string = "Property view options"             // Tooltip of property view commands.
        prop_ExpandAll:        string = "Expand all"                        // Expand every property group.
        prop_CollapseAll:      string = "Collapse all"                      // Collapse every property group.
        prop_ExpandModified:   string = "Expand modified"                   // Expand groups containing modified fields.
        prop_ShowModifiedOnly: string = "Show modified only"                // Restrict a property view to changed fields.

        // Wording of the [[Gui.ApplicationOptions]] rows a property grid generates from
        // reflection. An attribute value is a compile-time constant, so the declared English is
        // the key [[Gui.Properties.resolveText]] looks up; keep both sides in step.
        prop_CategoryDebug:       string = "Debug"                                                                        // Category of the development diagnostics.
        prop_ShowClipRect:        string = "Show Clip Rect"                                                               // Label of [[Gui.ApplicationOptions.showClipRect]].
        prop_ShowClipRectDesc:    string = "Display an overlay of the current drawing clipping rectangle"                 // Description of [[Gui.ApplicationOptions.showClipRect]].
        prop_ShowLayoutRects:     string = "Show Layout Rects"                                                            // Label of [[Gui.ApplicationOptions.showLayoutRects]].
        prop_ShowLayoutRectsDesc: string = "Display layout rectangles computed by layout controls"                        // Description of [[Gui.ApplicationOptions.showLayoutRects]].
        prop_ShowFocusRings:      string = "Show Focus Rings"                                                             // Label of [[Gui.ApplicationOptions.showFocusRings]].
        prop_ShowFocusRingsDesc:  string = "Draw the keyboard-focus ring on every control that can take the keyboard"     // Description of [[Gui.ApplicationOptions.showFocusRings]].
        prop_DumpLayoutTree:      string = "Dump Layout Tree"                                                             // Label of [[Gui.ApplicationOptions.dumpLayoutTree]].
        prop_DumpLayoutTreeDesc:  string = "Enable layout tree dumps from debug tooling"                                  // Description of [[Gui.ApplicationOptions.dumpLayoutTree]].
    }
}

private const FrenchStringsName = "lang/fr/gui.tweak"
private const FrenchStrings = #include(FrenchStringsName)

private var g_Strings: Strings

// Returns the visible strings of the GUI module in the active language.
func strings()->const *Strings => &g_Strings

// One language the interface can present.
//
// `en` is registered by the GUI module itself and always available: it names the
// reference wording declared by the string tables, so it needs no resource. Every other
// language is a tag whose tables are read from `lang/<tag>/<file>.tweak`.
struct Language
{
    public
    {
        tag:        String     // Short language tag, `"en"` or `"fr"`.
        nativeName: String     // Name of the language written in that language, never translated.
        builtin:    bool       // Whether the tag names the declared reference strings instead of a resource.
    }
}

// One registered string table: a live struct of `string` fields owned by a module or
// an application, plus the storage of its currently loaded translations.
private struct StringTable
{
    type: typeinfo = Strings     // Reflected type of the table.
    data: #null *void            // The live table the fields of which are retargeted.
    file: String                 // Base name of the per-language resource.

    // Decoded translation values. The table fields are views into these heap strings,
    // so the pool is only released after the table was reset to its reference values.
    pool: Array'(*String)
}

private struct LocalizationState
{
    tables:    Array'StringTable     // Registered tables, applied in registration order.
    languages: Array'Language        // Presentable languages, `ReferenceLanguage` first.
    language:  String                // Active tag; empty means the reference `"en"`.

    // Bundle the active language was applied from, borrowed for as long as it stays active.
    // A table registered after the switch is translated from it, which is what makes a
    // shared library loaded on demand arrive in the language already on screen.
    resources: #null const *Resources.Bundle
}

private var g_Localization: LocalizationState

// Registers a string table so language switches retarget it.
//
// `table` is borrowed for the whole program: a global of the module or the application
// that owns it, or of a shared library that is never unloaded, since a registration
// cannot be withdrawn. `file` names the per-language resource, resolved as
// `lang/<tag>/<file>.tweak`. Registering the same table again is a no-op.
//
// The table is translated on the spot when a language is already active, so a table that
// arrives with a library loaded on demand shows the language already on screen rather
// than waiting for the next switch. Add its resource to the bundle first. GUI thread only.
func(T) registerStrings(table: *T, file: string)
{
    #static if !Reflection.isStruct(T) do
        #error("a string table must be a struct of 'string' fields")
    registerStrings(#typeof(T), table, file)
}

// Registers a string table through its reflected type; prefer the typed overload.
func registerStrings(type: typeinfo, table: *void, file: string)
{
    Debug.assert(Reflection.isStruct(type), "a string table must be a struct of 'string' fields")

    let state = &g_Localization
    for &existing in state.tables where existing.data == table do
        return
    state.tables.add({type, table, file})

    // A table joining an already-translated program takes the active language now. A file it
    // has no translation for, or one a disk override left malformed, leaves it on its
    // reference wording — the same outcome [[Gui.applyLanguage]] gives an untranslated table.
    if state.language.isEmpty() or !state.resources do
        return
    discard catch applyTableLanguage(state.tables.backPtr(), state.resources!, state.language.toString())
}

// Returns the active language tag, `"en"` by default. The value is borrowed and
// stays valid until the next language switch.
func activeLanguage()->string => g_Localization.language.isEmpty() ? ReferenceLanguage : g_Localization.language.toString()

// Tag of the reference wording declared by the string tables.
const ReferenceLanguage = "en"

// Seeds the registry with the reference language on its first use.
//
// Doing it here rather than at module setup keeps [[Gui.ReferenceLanguage]] first in the
// list whoever registers first, and keeps it presentable to a program that never creates
// a surface.
private func ensureReferenceLanguage()
{
    let registry = &g_Localization.languages
    if registry.isEmpty() do
        registry.add({String.from(ReferenceLanguage), String.from("English"), true})
}

// Registers a language the interface can present.
//
// `tag` is a short language tag such as `"fr"`, and `nativeName` is the name of the
// language written in that language, because a picker lists it beside the others rather
// than inside a translated sentence. Registering a tag again replaces its name.
// [[Gui.ReferenceLanguage]] is always registered and always comes first. A module or an
// application registers its own tag next to the resources that carry it. GUI thread only.
func registerLanguage(tag, nativeName: string)
{
    Debug.assert(@countof(tag) != 0, "empty language tag")

    ensureReferenceLanguage()
    for &existing in g_Localization.languages where existing.tag == tag
    {
        existing.nativeName = nativeName
        return
    }

    g_Localization.languages.add({String.from(tag), String.from(nativeName), false})
}

// Returns the registered languages, [[Gui.ReferenceLanguage]] first.
//
// The elements are borrowed and stay valid until the next registration.
func languages()->const [..] Language
{
    ensureReferenceLanguage()
    return g_Localization.languages.toSlice()
}

// Returns the registered language named by `tag`, or `null` when no language carries it.
func findLanguage(tag: string)->#null const *Language
{
    ensureReferenceLanguage()
    for &one in g_Localization.languages where one.tag == tag do
        return one
    return null
}

// Returns the registered tag that best matches the language of the user account.
//
// The locale reported by [[Core.Env.userLocaleName]] is a full name such as `fr-FR`, so
// the primary language subtag decides: `fr-CA` selects a registered `fr`. Falls back to
// [[Gui.ReferenceLanguage]] when nothing matches, which is why an application can apply
// the result without handling a miss.
func systemLanguage()->string
{
    let locale  = Env.userLocaleName()
    let primary = Tokenize.sliceToDelimiter(locale.toString(), '-', includeDelimiter: false)
    let found   = findLanguage(primary)
    return found ? found.tag.toString() : ReferenceLanguage
}

// Applies the language `tag` to every registered string table.
//
// [[Gui.ReferenceLanguage]] restores the declared reference strings. Any other tag first
// resets each table, then decodes its `lang/<tag>/<file>.tweak` resource from
// `resources`; a table without a file for that tag keeps its reference strings.
//
// Fails without touching any table when the tag is not registered through
// [[Gui.registerLanguage]], or when no registered table has a file for it, so a mistyped
// tag cannot present itself as applied; a malformed file fails mid-way with the earlier
// tables already switched.
//
// `resources` is remembered while the tag stays active, so a table registered later is
// translated from the same bundle instead of waiting for the next switch. Prefer
// [[Application.setLanguage]], which also notifies every surface. GUI thread only.
func applyLanguage(resources: const *Resources.Bundle, tag: string) fail
{
    Debug.assert(@countof(tag) != 0, "empty language tag")

    let state = &g_Localization
    if !findLanguage(tag) do
        fail BadParameterError{Errors.mkString(Format.toString("language [[%]] is not registered", tag))}

    if tag != ReferenceLanguage
    {
        var anyFound = false
        for &table in state.tables where resources.has(langResourceName(tag, table.file).toString()) do
            anyFound = true
        if !anyFound do
            fail FileNotFoundError{fileName: Errors.mkString(tag)}
    }

    for &table in state.tables do
        try applyTableLanguage(table, resources, tag)

    state.language  = tag
    state.resources = resources
}

// Resets one table and decodes its resource for `tag`, leaving it on its reference
// strings when it has no file for that language.
private func applyTableLanguage(table: *StringTable, resources: const *Resources.Bundle, tag: string) fail
{
    resetTable(table)
    if tag == ReferenceLanguage do
        return

    let resName = langResourceName(tag, table.file)
    if !resources.has(resName.toString()) do
        return

    let bytes = try resources.load(resName.toString())
    try parseStringsContent(table.type, cast([*] u8) table.data!, cast(string) bytes.toSlice(), &table.pool)
}

// Decodes `content` against the string table type `T` without touching any live table.
//
// Intended for a `#run` block, so an embedded language file with a mistyped key or a
// non-string target is a build error carrying the faulty line, not a runtime surprise.
func(T) validateStrings(content: string) fail
{
    try validateStrings(#typeof(T), content)
}

// Decodes `content` against a reflected string table type; prefer the typed overload.
func validateStrings(type: typeinfo, content: string) fail
{
    Debug.assert(Reflection.isStruct(type), "a string table must be a struct of 'string' fields")

    // The probe only receives `string` views, so releasing the raw block is enough.
    let structType = cast(const *Swag.TypeInfoStruct) type
    let probe      = Memory.alloc(cast(u64) structType.sizeof)
    defer Memory.free(probe, cast(u64) structType.sizeof)
    if structType.opInit != null do
        structType.opInit(probe)
    else do
        Memory.clear(probe, cast(u64) structType.sizeof)

    try parseStringsContent(type, cast([*] u8) probe, content, null)
}

// Registers the GUI string table, the languages it ships, and its embedded translations.
internal func registerDefaultStrings(bundle: *Resources.Bundle)
{
    registerLanguage("fr", "Français")
    registerStrings'Strings(&g_Strings, "gui")
    bundle.addEmbedded(FrenchStringsName, FrenchStrings)
}

private func langResourceName(tag: string, file: String)->String
{
    var result: retval = "lang/"
    result += tag
    result += "/"
    result += file
    result += ".tweak"
    return result
}

// Restores the declared reference strings of a table, then releases its translations.
//
// The fields point into the pool, so the reset comes first and the pool is only
// released once no field can reference it anymore.
private func resetTable(table: *StringTable)
{
    let structType = cast(const *Swag.TypeInfoStruct) table.type
    let data       = table.data!
    if structType.opDrop != null do
        structType.opDrop(data)
    if structType.opInit != null do
        structType.opInit(data)
    else do
        Memory.clear(data, cast(u64) structType.sizeof)

    for entry in table.pool do
        Memory.delete(entry)
    table.pool.clear()
}

// Decodes one language file onto a string table.
//
// A line is `key value`, where `key` is a field name of the table and the value runs
// to the end of the line, leading blanks excluded. A value starting with `"` decodes
// as a quoted literal, which allows leading blanks and `""t`/`""n` escapes. A line
// starting with `#` is a comment; there are no inline comments, since prose owns the
// rest of the line. With a pool, decoded values are copied there and the table fields
// are pointed at them; without one, the content is only validated.
private func parseStringsContent(type: typeinfo, data: [*] u8, content: string, pool: #null *Array'(*String)) fail
{
    let lines = Tokenize.splitLines(content)
    for oneit, idx in lines
    {
        var one = Tokenize.eatSpaces(oneit)
        if @countof(one) == 0 do
            continue
        if one[0] == '#' do
            continue

        let id = catch StrConv.parseIdentifier(one) as idErr
        if idErr != null do
            fail SyntaxError{"invalid string key", line: idx + 1}

        let field = Reflection.findField(type, id)
        if !field do
            fail SyntaxError{Errors.mkString(Format.toString("string key [[%]] not found in [[%]]", id, type.name)), line: idx + 1}
        let safeField = field
        if safeField.pointedType != string do
            fail SyntaxError{Errors.mkString(Format.toString("string key [[%]] does not target a [[string]] field", id)), line: idx + 1}

        one = Tokenize.eatCount(one, @countof(id))
        one = Tokenize.eatSpaces(one)

        var value: String
        if @countof(one) and one[0] == '"' do
            discard try StrConv.parseString(&value, one)
        else do
            value = one

        if pool == null do
            continue

        // The table field becomes a view into a heap string the pool keeps alive; the
        // string never moves, so the view survives pool growth.
        let owned = Memory.new'String()
        owned[] = value
        pool.add(owned)
        (data + safeField.offset)[as string] = owned.toString()
    }
}

// Build-time validation of the embedded translations: a mistyped key in a language
// file is a compile error with its line number, not a runtime fallback.
#run
{
    expect validateStrings'Strings(cast(string) FrenchStrings)
}
