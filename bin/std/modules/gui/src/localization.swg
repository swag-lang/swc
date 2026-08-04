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
    dlg_Ok:           string = "OK"                           // Confirmation button of a dialog.
    dlg_Cancel:       string = "Cancel"                       // Cancel button of a dialog.
    dlg_Yes:          string = "Yes"                          // Positive answer button.
    dlg_No:           string = "No"                           // Negative answer button.
    dlg_Close:        string = "Close"                        // Close button of an informational dialog.
    dlg_ConfirmTitle: string = "Please confirm"               // Title of a confirmation dialog.
    dlg_ConfirmText:  string = "Do you want to continue?"     // Default question of a confirmation dialog.
    dlg_ErrorTitle:   string = "Error"                        // Title of an error dialog.

    fileDlg_TitleCreateFile:   string = "Create File"                                 // File dialog title when creating a file.
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

    browser_Shortcuts:    string = "Shortcuts"                                   // Locations pane group of user shortcuts.
    browser_Drives:       string = "Drives"                                      // Locations pane group of mounted drives.
    browser_Desktop:      string = "Desktop"                                     // Default shortcut to the desktop.
    browser_Documents:    string = "Documents"                                   // Default shortcut to the documents folder.
    browser_Pictures:     string = "Pictures"                                    // Default shortcut to the pictures folder.
    browser_ColName:      string = "Name"                                        // File list column of entry names.
    browser_ColModified:  string = "Modified"                                    // File list column of last write times.
    browser_AllFiles:     string = "All Files"                                   // Filter matching every extension.
    browser_Back:         string = "Back"                                        // Navigate to the previous folder.
    browser_Forward:      string = "Forward"                                     // Navigate to the next folder.
    browser_Up:           string = "Up"                                          // Navigate to the parent folder.
    browser_Refresh:      string = "Refresh"                                     // Reload the current folder.
    browser_NewFolder:    string = "New Folder"                                  // Create a folder in the current location.
    browser_TipBack:      string = "Previous folder (Alt+Left)"                  // Tooltip of [[browser_Back]].
    browser_TipForward:   string = "Next folder (Alt+Right)"                     // Tooltip of [[browser_Forward]].
    browser_TipUp:        string = "Parent folder (Alt+Up)"                      // Tooltip of [[browser_Up]].
    browser_TipRefresh:   string = "Refresh (F5)"                                // Tooltip of [[browser_Refresh]].
    browser_TipNewFolder: string = "Create a folder in the current location"     // Tooltip of [[browser_NewFolder]].
    browser_FolderName:   string = "Folder Name"                                 // Name field label when picking a folder.
    browser_FileName:     string = "File Name"                                   // Name field label when picking a file.
    browser_Folders:      string = "Folders"                                     // Type filter entry when picking a folder.
    browser_Type:         string = "Type"                                        // Label of the type filter field.

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
}

private const FrenchStringsName = "lang/fr/gui.tweak"
private const FrenchStrings = #include(FrenchStringsName)

private var g_Strings: Strings

// Returns the visible strings of the GUI module in the active language.
func strings()->const &Strings => &g_Strings

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
    tables:   Array'StringTable     // Registered tables, applied in registration order.
    language: String                // Active tag; empty means the reference `"en"`.
}

private var g_Localization: LocalizationState

// Registers a string table so language switches retarget it.
//
// `table` is borrowed for the whole program: it must be a global. `file` names the
// per-language resource, resolved as `lang/<tag>/<file>.tweak`. Registering the same
// table again is a no-op. Register before switching languages: a table registered
// afterwards keeps its reference strings until the next switch. GUI thread only.
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
}

// Returns the active language tag, `"en"` by default. The value is borrowed and
// stays valid until the next language switch.
func activeLanguage()->string => g_Localization.language.isEmpty() ? "en" : g_Localization.language.toString()

// Applies the language `tag` to every registered string table.
//
// `"en"` restores the declared reference strings. Any other tag first resets each
// table, then decodes its `lang/<tag>/<file>.tweak` resource from `resources`; a table
// without a file for that tag keeps its reference strings. Fails without touching any
// table when the tag has no file for any registered table, so a mistyped tag cannot
// present itself as applied; a malformed file fails mid-way with the earlier tables
// already switched. Prefer [[Application.setLanguage]], which also notifies every
// surface. GUI thread only.
func applyLanguage(resources: const *Resources.Bundle, tag: string) fail
{
    Debug.assert(@countof(tag) != 0, "empty language tag")

    let state = &g_Localization
    if tag != "en"
    {
        var anyFound = false
        for &table in state.tables where resources.has(langResourceName(tag, table.file).toString()) do
            anyFound = true
        if !anyFound do
            fail FileNotFoundError{fileName: Errors.mkString(tag)}
    }

    for &table in state.tables
    {
        resetTable(table)
        if tag == "en" do
            continue

        let resName = langResourceName(tag, table.file)
        if !resources.has(resName.toString()) do
            continue

        let bytes = try resources.load(resName.toString())
        try parseStringsContent(table.type, cast([*] u8) notnull table.data, cast(string) bytes.toSlice(), &table.pool)
    }

    state.language = tag
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

// Registers the GUI string table and its embedded translations.
internal func registerDefaultStrings(bundle: *Resources.Bundle)
{
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
    let data       = notnull table.data
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
    for oneit, [idx] in lines
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
        dref owned = value
        pool.add(owned)
        dref cast(*string) (data + safeField.offset) = owned.toString()
    }
}

// Build-time validation of the embedded translations: a mistyped key in a language
// file is a compile error with its line number, not a runtime fallback.
#run
{
    expect validateStrings'Strings(cast(string) FrenchStrings)
}
