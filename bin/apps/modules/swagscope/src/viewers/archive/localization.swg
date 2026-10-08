#global internal
#global namespace Viewers.Archive

using Core, Gui

// Visible strings of the archive viewer.
struct Texts
{
    ui_Name:                string = "Archive"
    ui_ColName:             string = "Name"
    ui_ColSize:             string = "Size"
    ui_Empty:               string = "This archive contains no files."
    ui_Select:              string = "Select a file to preview it."
    ui_Previewing:          string = "Preparing preview…"
    ui_PreviewError:        string = "This entry cannot be previewed."
    ui_Details:             string = "% entries · % unpacked · % packed"
    ui_SearchPlaceholder:   string = "Filter archive entries"
    err_ShortField16:       string = "ZIP record ends before a 16-bit field"     // Diagnostics of an archive the reader cannot open.
    err_ShortField32:       string = "ZIP record ends before a 32-bit field"
    err_ExtraField:         string = "ZIP extra field extends past its directory entry"
    err_Zip64Uncompressed:  string = "ZIP64 entry is missing its uncompressed size"
    err_Zip64Compressed:    string = "ZIP64 entry is missing its compressed size"
    err_Zip64Offset:        string = "ZIP64 entry is missing its local-header offset"
    err_Zip64Disk:          string = "ZIP64 entry is missing its disk number"
    err_Zip64Locator:       string = "ZIP64 end locator is missing"
    err_Zip64MultiDisk:     string = "multi-disk ZIP64 archives are not supported"
    err_Zip64EndOutside:    string = "ZIP64 end record lies outside the file"
    err_Zip64EndSignature:  string = "ZIP64 end record has the wrong signature"
    err_TooShort:           string = "file is too short to contain a ZIP end record"
    err_EndMissing:         string = "ZIP end record is missing"
    err_MultiDisk:          string = "multi-disk ZIP archives are not supported"
    err_TooManyEntries:     string = "ZIP archive contains too many entries"
    err_DirectoryTooLarge:  string = "ZIP central directory is too large"
    err_DirectoryOutside:   string = "ZIP central directory lies outside the file"
    err_DirectoryTruncated: string = "ZIP central directory ends inside an entry"
    err_EntrySignature:     string = "ZIP central-directory entry has the wrong signature"
    err_EntryOverflow:      string = "ZIP central-directory entry extends past the directory"
    err_MultiDiskEntry:     string = "multi-disk ZIP entries are not supported"
    err_EntrySizes:         string = "ZIP entry sizes exceed the supported range"
    err_DirectoryContent:   string = "a ZIP directory has no file content"
    err_Encrypted:          string = "encrypted ZIP entries are not supported"
    err_EntryTooLarge:      string = "ZIP entry is too large to preview"
    err_PackedTooLarge:     string = "compressed ZIP entry is too large to preview"
    err_Method:             string = "ZIP compression method % is not supported"     // Placeholder: the method number.
    err_LocalOutside:       string = "ZIP local header lies outside the file"
    err_LocalTruncated:     string = "ZIP local header is truncated"
    err_LocalSignature:     string = "ZIP local header has the wrong signature"
    err_LocalFields:        string = "ZIP local header fields lie outside the file"
    err_PayloadOutside:     string = "ZIP entry payload lies outside the file"
    err_PayloadTruncated:   string = "ZIP entry payload is truncated"
    err_SizeMismatch:       string = "ZIP entry expands to a different size than its directory declares"
    err_Checksum:           string = "ZIP entry checksum does not match its directory"
    err_TempWrite:          string = "temporary preview file was not written completely"
}

private const FrenchStringsName = "lang/fr/scope.archive.tweak"
private const FrenchStrings     = #include("../../../datas/lang/fr/scope.archive.tweak")

private var g_Texts: Texts

// Returns the visible strings of the archive viewer in the active language.
func texts()->const *Texts => &g_Texts

// Registers this viewer's strings before the registry names its plugin.
func registerTexts(app: *Application)
{
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)
    Gui.registerStrings'Texts(&g_Texts, "scope.archive")
}

#run
{
    expect Gui.validateStrings'Texts(cast(string, FrenchStrings))
}
