#include "pch.h"
#include "Backend/Native/NativeLinkerPe.h"
#include "Backend/Native/NativeArchive.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/NativeCoffReader.h"
#include "Backend/Micro/MachineCode.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/SourceFile.h"
#include "Main/FileSystem.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t DEFAULT_EXECUTABLE_STACK_RESERVE = 8u * 1024u * 1024u;
    constexpr uint64_t EXECUTABLE_IMAGE_BASE            = 0x140000000ull;
    constexpr uint64_t SHARED_LIBRARY_IMAGE_BASE        = 0x180000000ull;

    Utf8 normalizedLibName(std::string_view moduleName)
    {
        Utf8 lib{moduleName};
        lib.make_lower();
        if (fs::path(std::string(lib)).extension().empty())
            lib += ".lib";
        return lib;
    }

    // Gathers the link library required by every foreign function referenced by a code block. The
    // dependency-module hooks are themselves foreign functions, so this also pulls in dependency libs.
    void collectForeignLibs(const TaskContext& ctx, const MachineCode& code, std::set<Utf8>& out)
    {
        for (const MicroRelocation& relocation : code.codeRelocations)
        {
            if (relocation.kind != MicroRelocation::Kind::ForeignFunctionAddress || !relocation.targetSymbol)
                continue;
            const auto* function = relocation.targetSymbol->safeCast<SymbolFunction>();
            if (!function)
                continue;
            const std::string_view moduleName = function->foreignLinkModuleName().empty() ? function->foreignModuleName() : function->foreignLinkModuleName();
            if (!moduleName.empty())
                out.insert(normalizedLibName(moduleName));
        }
    }

    // Names defined across a set of objects.
    void collectDefined(const std::vector<CoffObject>& objects, std::unordered_set<Utf8>& defined)
    {
        for (const CoffObject& object : objects)
            for (const CoffInputSymbol& symbol : object.definedSymbols)
                defined.insert(symbol.name);
    }

    // Reloc targets that are not (yet) defined; debug sections are dropped by the merge, so ignore
    // their relocations here too.
    void collectUndefined(const CoffObject& object, const std::unordered_set<Utf8>& defined, std::unordered_set<Utf8>& undefined)
    {
        for (const CoffInputSection& section : object.sections)
        {
            if (section.name.view().starts_with(".debug"))
                continue;
            for (const CoffInputReloc& reloc : section.relocs)
            {
                if (!defined.contains(reloc.symbolName))
                    undefined.insert(reloc.symbolName);
            }
        }
    }
}

NativeLinkerPe::NativeLinkerPe(NativeBackendBuilder& builder) :
    NativeLinker(builder)
{
}

Result NativeLinkerPe::readObjects(std::vector<CoffObject>& outObjects)
{
    SWC_ASSERT(builder_ != nullptr);
    for (const NativeObjDescription& description : builder_->objectDescriptions)
    {
        FileSystem::IoErrorInfo ioError;
        std::vector<std::byte>  bytes;
        if (FileSystem::readBinaryFile(description.objPath, bytes, ioError) != Result::Continue)
            return builder_->reportError(DiagnosticId::cmd_err_native_link_failed, Diagnostic::ARG_BECAUSE, std::format("cannot read object '{}'", Utf8(description.objPath).view()));

        CoffObject object;
        Utf8       error;
        if (!readCoffObject(asByteSpan(bytes), object, error))
            return builder_->reportError(DiagnosticId::cmd_err_native_link_failed, Diagnostic::ARG_BECAUSE, error);
        outObjects.push_back(std::move(object));
    }

    return Result::Continue;
}

void NativeLinkerPe::collectLibrarySearch(std::set<Utf8>& outLibNames, std::vector<fs::path>& outDirs) const
{
    SWC_ASSERT(builder_ != nullptr);

    // Library names: every foreign-function and dependency-hook module.
    for (const Utf8& library : builder_->compiler().foreignLibs())
        outLibNames.insert(normalizedLibName(library.view()));
    for (const NativeFunctionInfo& info : builder_->functionInfos)
        if (info.machineCode)
            collectForeignLibs(builder_->ctx(), *info.machineCode, outLibNames);
    if (builder_->startup)
        collectForeignLibs(builder_->ctx(), builder_->startup->code, outLibNames);

    // Search directories: the SDK/MSVC library directories, then dependency link dirs and the folders
    // that hold imported-API artifacts.
    Os::WindowsToolchainPaths toolchain;
    Os::discoverWindowsToolchainPaths(toolchain);
    for (const fs::path& dir : {toolchain.vcLibPath, toolchain.sdkUmLibPath, toolchain.sdkUcrtLibPath})
        if (!dir.empty())
            outDirs.push_back(dir);

    for (const fs::path& dir : builder_->compiler().importedDependencyLinkDirs())
        outDirs.push_back(dir);

    for (const SourceFile* file : builder_->compiler().files())
    {
        if (!file || !file->hasFlag(FileFlagsE::ImportedApi) || !file->path().has_parent_path())
            continue;
        const fs::path parent = file->path().parent_path().lexically_normal();
        if (std::ranges::find(outDirs, parent) == outDirs.end())
            outDirs.push_back(parent);
    }
}

Result NativeLinkerPe::loadArchives(std::vector<NativeArchive>& outArchives)
{
    std::set<Utf8>        libNames;
    std::vector<fs::path> dirs;
    collectLibrarySearch(libNames, dirs);

    std::unordered_set<Utf8> loadedPaths;
    for (const Utf8& libName : libNames)
    {
        for (const fs::path& dir : dirs)
        {
            std::error_code ec;
            const fs::path  candidate = (dir / libName.c_str()).lexically_normal();
            if (!fs::exists(candidate, ec) || ec)
                continue;

            const Utf8 key = Utf8(candidate);
            if (!loadedPaths.insert(key).second)
                break;

            FileSystem::IoErrorInfo ioError;
            std::vector<std::byte>  bytes;
            if (FileSystem::readBinaryFile(candidate, bytes, ioError) != Result::Continue)
                break;

            NativeArchive archive;
            Utf8          error;
            if (archive.load(std::move(bytes), error))
                outArchives.push_back(std::move(archive));
            break;
        }
    }

    return Result::Continue;
}

Result NativeLinkerPe::resolveSymbols(std::vector<CoffObject>& objects, std::vector<NativeArchive>& archives, LinkImage& image)
{
    std::unordered_set<Utf8> defined;
    collectDefined(objects, defined);

    std::unordered_set<Utf8> undefined;
    for (const CoffObject& object : objects)
        collectUndefined(object, defined, undefined);

    std::unordered_set<Utf8> imported;
    std::vector<Utf8>        worklist(undefined.begin(), undefined.end());

    while (!worklist.empty())
    {
        const Utf8 symbol = std::move(worklist.back());
        worklist.pop_back();
        if (defined.contains(symbol) || imported.contains(symbol))
            continue;

        bool resolved = false;
        for (NativeArchive& archive : archives)
        {
            const uint32_t memberOffset = archive.memberOffsetForSymbol(symbol);
            if (memberOffset == 0)
                continue;

            Utf8          error;
            ArchiveImport archiveImport;
            if (archive.tryReadImport(memberOffset, archiveImport, error))
            {
                LinkImport import;
                import.dll        = archiveImport.dll;
                import.importName = archiveImport.importName;
                import.symbolName = symbol;
                import.ordinal    = archiveImport.ordinal;
                import.byOrdinal  = archiveImport.byOrdinal;
                import.isData     = archiveImport.isData;
                image.imports.push_back(std::move(import));
                imported.insert(symbol);
                resolved = true;
                break;
            }

            const ByteSpan memberBytes = archive.memberData(memberOffset, error);
            if (memberBytes.empty())
                continue;

            CoffObject pulled;
            if (!readCoffObject(memberBytes, pulled, error))
                continue;

            for (const CoffInputSymbol& sym : pulled.definedSymbols)
                defined.insert(sym.name);
            std::unordered_set<Utf8> newUndefined;
            collectUndefined(pulled, defined, newUndefined);
            for (const Utf8& u : newUndefined)
                if (!imported.contains(u))
                    worklist.push_back(u);

            objects.push_back(std::move(pulled));
            resolved = true;
            break;
        }

        SWC_UNUSED(resolved); // unresolved symbols are reported by the PE writer during relocation
    }

    Utf8 error;
    if (!mergeCoffObjectsIntoImage(objects, image, error))
        return builder_->reportError(DiagnosticId::cmd_err_native_link_failed, Diagnostic::ARG_BECAUSE, error);

    return Result::Continue;
}

namespace
{
    void appendU32(std::vector<std::byte>& out, uint32_t value)
    {
        for (int i = 0; i < 4; ++i)
            out.push_back(static_cast<std::byte>((value >> (i * 8)) & 0xFF));
    }
}

// Emits a self-contained `.swagdbg` symbol table (function name + source location per function, keyed
// by image-relative address) so the runtime can symbolize stack traces without a PDB or dbghelp. The
// function addresses are written as Rva32 relocations resolved by the PE writer.
void NativeLinkerPe::buildDebugTable(LinkImage& image) const
{
    SWC_ASSERT(builder_ != nullptr);

    struct Entry
    {
        Utf8     symbolName;
        Utf8     name;
        Utf8     file;
        uint32_t line = 0;
        uint32_t size = 0;
    };

    std::vector<Entry> entries;
    entries.reserve(builder_->functionInfos.size());
    for (const NativeFunctionInfo& info : builder_->functionInfos)
    {
        if (!info.machineCode)
            continue;

        Entry entry;
        entry.symbolName = info.symbolName;
        entry.name       = info.debugName.empty() ? info.symbolName : info.debugName;
        entry.size       = static_cast<uint32_t>(info.machineCode->bytes.size());

        MachineCode::ResolvedDebugSourceRange resolved;
        if (info.machineCode->tryResolveDebugSourceRangeAtOffset(builder_->ctx(), resolved, 0) && resolved.source.sourceFile)
        {
            entry.file = Utf8(resolved.source.sourceFile->path());
            entry.line = resolved.source.codeRange.line;
        }
        entries.push_back(std::move(entry));
    }

    if (entries.empty())
        return;

    // String blob with de-duplication; offsets are relative to the start of the section.
    std::vector<std::byte>             strings;
    std::unordered_map<Utf8, uint32_t> stringOffsets;
    const uint32_t                     headerSize = 16;
    const uint32_t                     entrySize  = 20;
    const uint32_t                     blobBase   = headerSize + static_cast<uint32_t>(entries.size()) * entrySize;
    const auto                         internString = [&](const Utf8& s) -> uint32_t {
        if (s.empty())
            return 0;
        const auto it = stringOffsets.find(s);
        if (it != stringOffsets.end())
            return it->second;
        const uint32_t offset = blobBase + static_cast<uint32_t>(strings.size());
        stringOffsets.emplace(s, offset);
        strings.insert(strings.end(), reinterpret_cast<const std::byte*>(s.data()), reinterpret_cast<const std::byte*>(s.data()) + s.size());
        strings.push_back(std::byte{0});
        return offset;
    };

    LinkSection section;
    section.name  = ".swagdbg";
    section.align = 4;

    appendU32(section.bytes, 0x42445753u); // 'SWDB'
    appendU32(section.bytes, 1);           // version
    appendU32(section.bytes, static_cast<uint32_t>(entries.size()));
    appendU32(section.bytes, blobBase);    // string blob start (section-relative)

    for (const Entry& entry : entries)
    {
        const uint32_t nameOff = internString(entry.name);
        const uint32_t fileOff = internString(entry.file);

        LinkReloc reloc;
        reloc.sectionIndex = static_cast<uint32_t>(image.sections.size());
        reloc.offset       = static_cast<uint32_t>(section.bytes.size());
        reloc.symbolName   = entry.symbolName;
        reloc.kind         = LinkRelocKind::Rva32;
        section.relocs.push_back(std::move(reloc));

        appendU32(section.bytes, 0); // rva, filled by the writer
        appendU32(section.bytes, entry.size);
        appendU32(section.bytes, nameOff);
        appendU32(section.bytes, fileOff);
        appendU32(section.bytes, entry.line);
    }

    section.bytes.insert(section.bytes.end(), strings.begin(), strings.end());
    image.sections.push_back(std::move(section));
}

void NativeLinkerPe::collectExports(LinkImage& image) const
{
    SWC_ASSERT(builder_ != nullptr);
    for (const NativeFunctionInfo& info : builder_->functionInfos)
    {
        if (!info.exported)
            continue;
        LinkExport exported;
        exported.name       = info.symbolName;
        exported.symbolName = info.symbolName;
        image.exports.push_back(std::move(exported));
    }
}

Result NativeLinkerPe::buildImage(LinkImage& image)
{
    SWC_ASSERT(builder_ != nullptr);

    std::vector<CoffObject> objects;
    SWC_RESULT(readObjects(objects));

    std::vector<NativeArchive> archives;
    SWC_RESULT(loadArchives(archives));

    SWC_RESULT(resolveSymbols(objects, archives, image));

    // Emit the embedded `.swagdbg` symbol table consumed by the runtime self-symbolizer.
    buildDebugTable(image);

    image.moduleName = Utf8(builder_->artifactPath.filename());

    const bool isDll = builder_->compiler().buildCfg().backendKind == Runtime::BuildCfgBackendKind::SharedLibrary;
    if (isDll)
    {
        image.kind      = LinkImageKind::SharedLibrary;
        image.imageBase = SHARED_LIBRARY_IMAGE_BASE;
        collectExports(image);
    }
    else
    {
        image.kind      = LinkImageKind::Executable;
        image.imageBase = EXECUTABLE_IMAGE_BASE;
        if (builder_->startup)
            image.entrySymbol = builder_->startup->symbolName;
    }

    image.stackReserve = DEFAULT_EXECUTABLE_STACK_RESERVE;
    return Result::Continue;
}

Result NativeLinkerPe::prepareLink(NativeLinkJob& outJob)
{
    SWC_ASSERT(builder_ != nullptr);
    outJob.outputPath = builder_->artifactPath;
    outJob.buildDir   = builder_->buildDir;

    switch (builder_->compiler().buildCfg().backendKind)
    {
        case Runtime::BuildCfgBackendKind::Executable:
            outJob.output = NativeLinkJob::Output::Executable;
            return buildImage(outJob.image);
        case Runtime::BuildCfgBackendKind::SharedLibrary:
            outJob.output = NativeLinkJob::Output::SharedLibrary;
            return buildImage(outJob.image);
        case Runtime::BuildCfgBackendKind::StaticLibrary:
            outJob.output = NativeLinkJob::Output::StaticLibrary;
            for (const NativeObjDescription& description : builder_->objectDescriptions)
                outJob.archiveMembers.push_back(description.objPath);
            return Result::Continue;
        case Runtime::BuildCfgBackendKind::Export:
        case Runtime::BuildCfgBackendKind::None:
            SWC_UNREACHABLE();
    }

    SWC_UNREACHABLE();
}

SWC_END_NAMESPACE();
