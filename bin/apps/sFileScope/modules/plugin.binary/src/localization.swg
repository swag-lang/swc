#global public

using Core, Gui

// Visible strings of the binary format viewer.
//
// Only prose is translated. The names a format gives its own structures and fields — `SizeOfImage`,
// `e_lfanew`, `DT_NEEDED`, `.text`, `IMAGE_SCN_MEM_EXECUTE` — are identifiers a reader looks up in
// that format's documentation, so they are written exactly as the specification writes them in
// every language. The same holds for the names of machines, subsystems and resource types: those
// are proper names, not sentences.
struct BinaryStrings
{
    ui_ColField:     string = "Field"                            // Header of the structure column.
    ui_ColValue:     string = "Value"                            // Header of the decoded value column.
    ui_ColOffset:    string = "Offset"                           // Header of the file offset column.
    ui_ColDetail:    string = "Meaning"                          // Header of the explanation column.
    ui_TipMenu:      string = "Copy and layout"                  // Tooltip of the command menu button.
    ui_TipExpand:    string = "Expand everything (Ctrl+E)"       // Tooltip while the tree is collapsed.
    ui_TipCollapse:  string = "Collapse everything (Ctrl+E)"     // Tooltip while the tree is expanded.
    ui_MenuCopyAll:  string = "Copy the whole report"            // Menu entry copying every row.
    ui_MenuCopyLine: string = "Copy this line"                   // Menu entry copying the selected row.
    ui_MenuExpand:   string = "Expand everything"                // Menu entry opening every group.
    ui_MenuCollapse: string = "Collapse everything"              // Menu entry closing every group.
    ui_Unreadable:   string = "This file could not be read."     // Shown when the file cannot be opened.

    word_Section:    string = "section"        // One section.
    word_Sections:   string = "sections"       // Several sections.
    word_Entry:      string = "entry"          // One entry of any table.
    word_Entries:    string = "entries"        // Several entries of any table.
    word_Symbol:     string = "symbol"         // One named symbol.
    word_Symbols:    string = "symbols"        // Several named symbols.
    word_Module:     string = "module"         // One imported module.
    word_Modules:    string = "modules"        // Several imported modules.
    word_Object:     string = "object"         // One compiled object.
    word_Objects:    string = "objects"        // Several compiled objects.
    word_Page:       string = "page"           // One relocated page.
    word_Pages:      string = "pages"          // Several relocated pages.
    word_Fixup:      string = "fixup"          // One relocation entry.
    word_Fixups:     string = "fixups"         // Several relocation entries.
    word_Member:     string = "member"         // One archive member.
    word_Members:    string = "members"        // Several archive members.
    word_Chunk:      string = "chunk"          // One container payload.
    word_Chunks:     string = "chunks"         // Several container payloads.
    word_Record:     string = "record"         // One fixed-size record.
    word_Records:    string = "records"        // Several fixed-size records.
    word_Library:    string = "library"        // One shared library.
    word_Libraries:  string = "libraries"      // Several shared libraries.
    word_Property:   string = "property"       // One metadata property.
    word_Properties: string = "properties"     // Several metadata properties.

    shr_Sections:    string = "Sections"                                                  // Group of whatever a format calls a section.
    shr_Imports:     string = "Imports"                                                   // Group of what a file needs from elsewhere.
    shr_Exports:     string = "Exports"                                                   // Group of what a file offers to others.
    shr_Libraries:   string = "Required libraries"                                        // Group listing the libraries a file needs.
    shr_BuildId:     string = "Build identity"                                            // Row giving a build fingerprint.
    shr_Interpreter: string = "Interpreter"                                               // Row giving the program interpreter or loader.
    shr_Entry:       string = "Entry point"                                               // Row giving where execution starts.
    shr_Malformed:   string = "the chain of records stops before the end of the file"     // Broken layout.

    rep_File:        string = "File"                                             // Group naming the file itself.
    rep_Size:        string = "Size"                                             // Row giving the size on disk.
    rep_Read:        string = "Read"                                             // Row giving how much was analyzed.
    rep_Bounded:     string = "only the beginning of this file was analyzed"     // Detail of a bounded analysis.
    rep_Truncated:   string = "a structure runs past the end of the file"        // Warning about an unreadable field.
    rep_FirstBytes:  string = "First bytes"                                      // Row showing the leading signature.
    rep_Entropy:     string = "Entropy"                                          // Row estimating byte disorder.
    rep_EntropyHigh: string = "compressed, packed, or encrypted"                 // High-entropy reading.
    rep_EntropyMid:  string = "mixed code and data"                              // Middling-entropy reading.
    rep_EntropyLow:  string = "structured or textual"                            // Low-entropy reading.
    rep_NotListed:   string = "% more entries not listed"                        // Written where a long list was cut.
    rep_Unknown:     string = "Unrecognized binary"                              // Format name of a file nothing claims.
    rep_UnknownDesc: string = "no reader recognized this file"                   // Summary of a file nothing claims.
    rep_Empty:       string = "empty file"                                       // Summary of a file with no bytes.

    pe_DosHeader:      string = "DOS header"                                             // Group of the leading DOS header.
    pe_DosSignature:   string = "MS-DOS executable signature"                            // Meaning of the `MZ` magic.
    pe_DosLfanew:      string = "file offset of the PE signature"                        // Meaning of `e_lfanew`.
    pe_DosStub:        string = "DOS stub"                                               // Row holding the stub message.
    pe_DosStubDesc:    string = "message the image prints when run under DOS"            // Meaning of the stub message.
    pe_Rich:           string = "Rich header"                                            // Group of the toolchain fingerprint.
    pe_RichDesc:       string = "toolchain that produced the image"                      // Meaning of the Rich header.
    pe_RichKey:        string = "key every entry is masked with"                         // Meaning of the Rich checksum.
    pe_RichTool:       string = "product %, build %"                                     // One Rich header entry.
    pe_FileHeader:     string = "File header"                                            // Group of the COFF file header.
    pe_Optional:       string = "Optional header"                                        // Group of the optional header.
    pe_NoOptional:     string = "this file carries no optional header"                   // Written when the header is absent.
    pe_Image64:        string = "64-bit image"                                           // Meaning of the PE32+ magic.
    pe_Image32:        string = "32-bit image"                                           // Meaning of the PE32 magic.
    pe_ImageRom:       string = "ROM image"                                              // Meaning of the ROM magic.
    pe_NoEntry:        string = "no entry point"                                         // Meaning of a zero entry point.
    pe_PreferredBase:  string = "preferred load address"                                 // Meaning of `ImageBase`.
    pe_InMemory:       string = "in memory"                                              // Meaning of `SectionAlignment`.
    pe_OnDisk:         string = "on disk"                                                // Meaning of `FileAlignment`.
    pe_Reserved:       string = "bytes the loader reserves"                              // Meaning of `SizeOfImage`.
    pe_NoChecksum:     string = "not computed"                                           // Meaning of a zero checksum.
    pe_Directories:    string = "Data directories"                                       // Group of the directory table.
    pe_DirEmpty:       string = "empty"                                                  // Value of an unused directory.
    pe_ExportName:     string = "name the image exports under"                           // Meaning of the export name.
    pe_ExportBase:     string = "first ordinal"                                          // Meaning of the ordinal base.
    pe_ByName:         string = "By name"                                                // Group of named exports.
    pe_ByOrdinal:      string = "By ordinal only"                                        // Group of unnamed exports.
    pe_ByOrdinalDesc:  string = "symbols nothing can reach by name"                      // Meaning of an unnamed export.
    pe_Ordinal:        string = "ordinal %"                                              // Label naming one ordinal.
    pe_Forwarded:      string = "forwarded to %"                                         // Export answered by another module.
    pe_NotExported:    string = "not exported"                                           // Export slot nothing fills.
    pe_ExportOutside:  string = "the export directory is outside every section"          // Unreachable export directory.
    pe_ExportTableOut: string = "the export address table is outside every section"      // Unreachable export table.
    pe_ImportOutside:  string = "the import directory is outside every section"          // Unreachable import directory.
    pe_ImportTotal:    string = "Total"                                                  // Row totalling imported symbols.
    pe_ImportSymbols:  string = "imported symbols"                                       // Unit of the import total.
    pe_ImportLookup:   string = "import lookup table"                                    // Meaning of `OriginalFirstThunk`.
    pe_ImportAddress:  string = "import address table"                                   // Meaning of `FirstThunk`.
    pe_Bound:          string = "bound to a specific build"                              // Meaning of a set import stamp.
    pe_Unbound:        string = "not bound"                                              // Meaning of a zero import stamp.
    pe_ByOrdinalBind:  string = "bound by ordinal"                                       // Import that carries no name.
    pe_Hint:           string = "hint %"                                                 // Lookup hint of a named import.
    pe_ThunkOutside:   string = "this module's thunk table is outside every section"     // Unreachable thunk table.
    pe_Outside:        string = "outside every section"                                  // Address nothing in the file holds.
    pe_Delayed:        string = "Delayed imports"                                        // Group of the delay-load directory.
    pe_DelayedDesc:    string = "modules loaded on first use"                            // Meaning of a delayed import.
    pe_DelayRelative:  string = "addresses are relative to the image"                    // Meaning of the relative attribute.
    pe_DelayAbsolute:  string = "addresses are absolute"                                 // Meaning of the absolute attribute.
    pe_Resources:      string = "Resources"                                              // Group of the resource tree.
    pe_ResourceOut:    string = "the resource directory is outside every section"        // Unreachable resource directory.
    pe_Unnamed:        string = "(unnamed)"                                              // Resource whose name is empty.
    pe_ResourceType:   string = "type %"                                                 // Application-defined resource type.
    pe_ResourceId:     string = "id %"                                                   // Numbered resource.
    pe_ResourceLang:   string = "language %"                                             // Language of one resource.
    pe_ResourceWhere:  string = "code page %, at %"                                      // Where one resource payload sits.
    pe_Version:        string = "Version information"                                    // Group of the version resource.
    pe_VersionDesc:    string = "what the file's property page shows"                    // Meaning of the version resource.
    pe_VersionMissing: string = "the version resource carries no fixed block"            // Malformed version resource.
    pe_Debug:          string = "Debug information"                                      // Group of the debug directory.
    pe_DebugIdentity:  string = "identity the symbol file must carry"                    // Meaning of the CodeView GUID.
    pe_Exception:      string = "Exception directory"                                    // Group of the unwind table.
    pe_ExceptionDesc:  string = "functions with unwind information"                      // Meaning of the unwind count.
    pe_Coverage:       string = "Coverage"                                               // Row totalling unwind records.
    pe_Relocations:    string = "Base relocations"                                       // Group of the relocation table.
    pe_Pages:          string = "Pages"                                                  // Row counting relocated pages.
    pe_Fixups:         string = "Fixups"                                                 // Row counting relocation entries.
    pe_Tls:            string = "Thread local storage"                                   // Group of the TLS directory.
    pe_LoadConfig:     string = "Load configuration"                                     // Group of the load config directory.
    pe_Cookie:         string = "stack guard the image checks"                           // Meaning of the security cookie.
    pe_Clr:            string = "CLR header"                                             // Group of the managed header.
    pe_ClrManaged:     string = "managed image"                                          // Value naming a managed image.
    pe_ClrRuntime:     string = "framework the assembly targets"                         // Meaning of the metadata version.
    pe_Certificates:   string = "Signature"                                              // Group of the certificate table.
    pe_CertificateAt:  string = "appended after the image"                               // Where the signature sits.
    pe_CertificateNo:  string = "the signature block holds no readable certificate"      // Malformed signature block.
    pe_Certificate:    string = "certificate %"                                          // Label of one certificate.
    pe_Symbols:        string = "Symbols"                                                // Group of the COFF symbol table.
    pe_StringTable:    string = "String table"                                           // Row giving the string table size.
    pe_SymbolWhere:    string = "% · section %"                                          // Class and section of one symbol.

    elf_Header:       string = "ELF header"                                   // Group of the leading ELF header.
    elf_Identity:     string = "Identity"                                     // Group of the sixteen identity bytes.
    elf_Class32:      string = "32-bit objects"                               // Meaning of `ELFCLASS32`.
    elf_Class64:      string = "64-bit objects"                               // Meaning of `ELFCLASS64`.
    elf_Little:       string = "little endian"                                // Meaning of `ELFDATA2LSB`.
    elf_Big:          string = "big endian"                                   // Meaning of `ELFDATA2MSB`.
    elf_Programs:     string = "Program headers"                              // Group of the load segments.
    elf_ProgramsDesc: string = "what the loader maps"                         // Meaning of the program headers.
    elf_SectionsDesc: string = "what the linker works with"                   // Meaning of the section headers.
    elf_Dynamic:      string = "Dynamic section"                              // Group of the dynamic entries.
    elf_DynamicDesc:  string = "what the dynamic loader is told"              // Meaning of the dynamic section.
    elf_NoSections:   string = "the section headers are outside the file"     // Unreachable section table.

    ar_Archive:    string = "Archive"                                           // Group naming the archive itself.
    ar_Members:    string = "Members"                                           // Group listing the archive members.
    ar_Linker:     string = "Linker directory"                                  // Group of a symbol index member.
    ar_LinkerDesc: string = "which member defines which symbol"                 // Meaning of a symbol index.
    ar_LongNames:  string = "Long names"                                        // Member holding the long file names.
    ar_Modified:   string = "Modified"                                          // Row giving a member timestamp.
    ar_Mode:       string = "Mode"                                              // Row giving the member file mode.
    ar_Owner:      string = "Owner"                                             // Row giving the member user and group.
    ar_Import:     string = "Import descriptor"                                 // Member describing one imported symbol.
    ar_ImportDll:  string = "provided by %"                                     // Library one import member points at.
    ar_Malformed:  string = "the member chain stops before the end of file"     // Broken archive layout.

    scc_Container:   string = "Container"                                        // Group naming the SCC envelope.
    scc_Prefix:      string = "Prefix"                                           // Group of the fixed leading bytes.
    scc_Manifest:    string = "Manifest"                                         // Group of the header manifest.
    scc_Entries:     string = "Virtual entries"                                  // Group of the manifest hierarchy.
    scc_Chunks:      string = "Chunks"                                           // Group of the payload directory.
    scc_Properties:  string = "Properties"                                       // Group of the metadata properties.
    scc_Tags:        string = "Tags"                                             // Row listing the manifest tags.
    scc_Created:     string = "Created"                                          // Row giving the creation time.
    scc_Modified:    string = "Modified"                                         // Row giving the modification time.
    scc_Directory:   string = "directory"                                        // Kind of a virtual directory.
    scc_VirtualFile: string = "file"                                             // Kind of a virtual file.
    scc_Stored:      string = "stored"                                           // Chunk kept without compression.
    scc_Deflate:     string = "deflate"                                          // Chunk compressed with deflate.
    scc_Codec:       string = "custom codec"                                     // Chunk compressed by a registered codec.
    scc_Unreadable:  string = "this container's header could not be decoded"     // Rejected SCC header.
    scc_Profile:     string = "Profile data"                                     // Row giving the profile header size.

    mo_Header:       string = "Mach-O header"                     // Group of the leading Mach-O header.
    mo_Commands:     string = "Load commands"                     // Group of the load command chain.
    mo_CommandsDesc: string = "what the loader is told to do"     // Meaning of the load commands.
    mo_Fat:          string = "Universal binary"                  // Group of a multi-architecture wrapper.
    mo_FatDesc:      string = "one image per architecture"        // Meaning of a universal binary.
    mo_Architecture: string = "Architecture"                      // One slice of a universal binary.
    mo_Protection:   string = "maximum %, initial %"              // Page protection of one segment.
    mo_Slice:        string = "slice %"                           // Label of one architecture slice.

    zip_Directory:     string = "Central directory"                  // Group of the archive index.
    zip_DirectoryDesc: string = "what the archive says it holds"     // Meaning of the central directory.
    zip_End:           string = "End of central directory"           // Group of the trailing record.
    zip_Zip64:         string = "Zip64 locator"                      // Row naming the 64-bit extension.
    zip_Comment:       string = "Comment"                            // Row giving the archive comment.
    zip_Method:        string = "Method"                             // Row giving the compression method.
    zip_Ratio:         string = "packed to %{#0}%% of its size"      // How much one entry was reduced.
    zip_Encrypted:     string = "encrypted"                          // Entry whose payload is protected.
    zip_Folder:        string = "folder"                             // Entry that holds no payload.
    zip_NoDirectory:   string = "no central directory was found"     // Broken or split archive.

    wasm_Module:    string = "WebAssembly module"                                       // Format name of a Wasm module.
    wasm_Custom:    string = "Custom section"                                           // Group of a non-standard section.
    wasm_Function:  string = "function"                                                 // Import or export of a function.
    wasm_Table:     string = "table"                                                    // Import or export of a table.
    wasm_Memory:    string = "memory"                                                   // Import or export of a memory.
    wasm_Global:    string = "global"                                                   // Import or export of a global.
    wasm_Malformed: string = "the section chain stops before the end of the module"     // Broken module.

    riff_Container: string = "RIFF container"     // Format name of a RIFF file.
    riff_Chunks:    string = "Chunks"             // Group of the chunk chain.
    riff_Form:      string = "Form"               // Row giving the form the container carries.

    font_Font:       string = "Font"                          // Format name of an sfnt font.
    font_Tables:     string = "Tables"                        // Group of the table directory.
    font_TablesDesc: string = "what the rasterizer reads"     // Meaning of the table directory.
    font_Names:      string = "Names"                         // Group of the naming table.
    font_Family:     string = "Family"                        // Row giving the font family name.
    font_Subfamily:  string = "Subfamily"                     // Row giving the style within the family.
    font_FullName:   string = "Full name"                     // Row giving the complete font name.
    font_Version:    string = "Version"                       // Row giving the font version string.
    font_Glyphs:     string = "Glyphs"                        // Row counting the glyphs the font holds.
    font_UnitsPerEm: string = "Units per em"                  // Row giving the design grid size.
    font_Collection: string = "Font collection"               // Format name of a collection of fonts.
}

private const FrenchStringsName = "lang/fr/filescope.binary.tweak"
private const FrenchStrings = #include("../datas/lang/fr/filescope.binary.tweak")

private var g_BinaryStrings: BinaryStrings

// Returns the visible strings of the binary viewer in the active language.
func binStrings()->const *BinaryStrings => &g_BinaryStrings

// Registers this plugin's string table with the host that loaded it.
//
// A plugin enters the process long after the host chose a language, and the localization registry
// only fills a table when a language is applied. So the resource is published into the host's
// bundle and the active language is applied again, which is what makes a lazily loaded viewer
// speak the same language as the window around it.
func registerBinaryStrings(app: *Application)
{
    Gui.registerStrings'BinaryStrings(&g_BinaryStrings, "filescope.binary")
    app.resources.addEmbedded(FrenchStringsName, FrenchStrings)

    let active = Gui.activeLanguage()
    if active != Gui.ReferenceLanguage do
        discard catch Gui.applyLanguage(&app.resources, active)
}

// Returns `count` followed by the noun in the form that count calls for.
func countText(count: u64, singular, plural: string)->String
{
    return Format.toString("% %", count, count == 1 ? singular : plural)
}

#run
{
    expect Gui.validateStrings'BinaryStrings(cast(string) FrenchStrings)
}
