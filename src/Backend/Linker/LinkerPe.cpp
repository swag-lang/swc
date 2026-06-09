#include "pch.h"
#include "Backend/Linker/LinkerPe.h"
#include "Backend/Linker/Archive.h"
#include "Backend/Linker/CoffReader.h"
#include "Backend/Micro/MachineCode.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/SourceFile.h"
#include "Main/FileSystem.h"
#include "Support/Core/ByteUtils.h"

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
    void collectForeignLibs(std::set<Utf8>& outLibNames, const MachineCode& code)
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
                outLibNames.insert(normalizedLibName(moduleName));
        }
    }

    // Names defined across a set of objects.
    void collectDefined(std::unordered_set<Utf8>& outDefined, const std::vector<CoffObject>& objects)
    {
        for (const CoffObject& object : objects)
            for (const CoffInputSymbol& symbol : object.definedSymbols)
                outDefined.insert(symbol.name);
    }

    // Reloc targets that are not (yet) defined; debug sections are dropped by the merge, so ignore
    // their relocations here too.
    void collectUndefined(std::unordered_set<Utf8>& outUndefined, const CoffObject& object, const std::unordered_set<Utf8>& defined)
    {
        for (const CoffInputSection& section : object.sections)
        {
            if (section.name.view().starts_with(".debug"))
                continue;
            for (const CoffInputReloc& reloc : section.relocs)
            {
                if (!defined.contains(reloc.symbolName))
                    outUndefined.insert(reloc.symbolName);
            }
        }
    }
}

LinkerPe::LinkerPe(NativeBackendBuilder& builder) :
    Linker(builder)
{
}

Result LinkerPe::readObjects(std::vector<CoffObject>& outObjects) const
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
        if (!readCoffObject(object, error, asByteSpan(bytes)))
            return builder_->reportError(DiagnosticId::cmd_err_native_link_failed, Diagnostic::ARG_BECAUSE, error);
        outObjects.push_back(std::move(object));
    }

    return Result::Continue;
}

void LinkerPe::collectLibrarySearch(std::set<Utf8>& outLibNames, std::vector<fs::path>& outDirs) const
{
    SWC_ASSERT(builder_ != nullptr);

    // Library names: every foreign-function and dependency-hook module.
    for (const Utf8& library : builder_->compiler().foreignLibs())
        outLibNames.insert(normalizedLibName(library.view()));
    for (const NativeFunctionInfo& info : builder_->functionInfos)
        if (info.machineCode)
            collectForeignLibs(outLibNames, *info.machineCode);
    if (builder_->startup)
        collectForeignLibs(outLibNames, builder_->startup->code);

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

Result LinkerPe::loadArchives(std::vector<Archive>& outArchives) const
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

            const auto key = Utf8(candidate);
            if (!loadedPaths.insert(key).second)
                break;

            FileSystem::IoErrorInfo ioError;
            std::vector<std::byte>  bytes;
            if (FileSystem::readBinaryFile(candidate, bytes, ioError) != Result::Continue)
                break;

            Archive archive;
            Utf8    error;
            if (archive.load(error, std::move(bytes)))
                outArchives.push_back(std::move(archive));
            break;
        }
    }

    return Result::Continue;
}

Result LinkerPe::resolveSymbols(LinkImage& image, std::vector<CoffObject>& objects, std::vector<Archive>& archives) const
{
    std::unordered_set<Utf8> defined;
    collectDefined(defined, objects);

    std::unordered_set<Utf8> undefined;
    for (const CoffObject& object : objects)
        collectUndefined(undefined, object, defined);

    std::unordered_set<Utf8> imported;
    std::vector              worklist(undefined.begin(), undefined.end());

    while (!worklist.empty())
    {
        const Utf8 symbol = std::move(worklist.back());
        worklist.pop_back();
        if (defined.contains(symbol) || imported.contains(symbol))
            continue;

        for (Archive& archive : archives)
        {
            const uint32_t memberOffset = archive.memberOffsetForSymbol(symbol);
            if (memberOffset == 0)
                continue;

            Utf8          error;
            ArchiveImport archiveImport;
            if (archive.tryReadImport(archiveImport, error, memberOffset))
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
                break;
            }

            const ByteSpan memberBytes = archive.memberData(error, memberOffset);
            if (memberBytes.empty())
                continue;

            CoffObject pulled;
            if (!readCoffObject(pulled, error, memberBytes))
                continue;

            for (const CoffInputSymbol& sym : pulled.definedSymbols)
                defined.insert(sym.name);
            std::unordered_set<Utf8> newUndefined;
            collectUndefined(newUndefined, pulled, defined);
            for (const Utf8& u : newUndefined)
                if (!imported.contains(u))
                    worklist.push_back(u);

            objects.push_back(std::move(pulled));
            break;
        }
    }

    Utf8 error;
    if (!mergeCoffObjectsIntoImage(image, error, objects))
        return builder_->reportError(DiagnosticId::cmd_err_native_link_failed, Diagnostic::ARG_BECAUSE, error);

    return Result::Continue;
}

namespace
{
    struct DebugStringTable
    {
        uint32_t insert(const Utf8& value)
        {
            if (value.empty())
                return 0;
            const auto it = offsets.find(value);
            if (it != offsets.end())
                return it->second;

            const uint32_t offset = blobBase + static_cast<uint32_t>(bytes.size());
            offsets.emplace(value, offset);
            ByteUtils::appendCString(bytes, value.view());
            return offset;
        }

        uint32_t                           blobBase = 0;
        std::vector<std::byte>             bytes;
        std::unordered_map<Utf8, uint32_t> offsets;
    };
}

// Emits a self-contained `.swagdbg` symbol table (function name + source location per function, keyed
// by image-relative address) so the runtime can symbolize stack traces without a PDB or dbghelp. The
// function addresses are written as Rva32 relocations resolved by the PE writer.
void LinkerPe::buildDebugTable(LinkImage& image) const
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

    constexpr uint32_t headerSize = 16;
    constexpr uint32_t entrySize  = 20;

    DebugStringTable strings;
    strings.blobBase = headerSize + static_cast<uint32_t>(entries.size()) * entrySize;

    LinkSection section;
    section.name  = ".swagdbg";
    section.align = 4;

    ByteUtils::appendLE32(section.bytes, 0x42445753u); // 'SWDB'
    ByteUtils::appendLE32(section.bytes, 1);           // version
    ByteUtils::appendLE32(section.bytes, static_cast<uint32_t>(entries.size()));
    ByteUtils::appendLE32(section.bytes, strings.blobBase);

    for (const Entry& entry : entries)
    {
        const uint32_t nameOff = strings.insert(entry.name);
        const uint32_t fileOff = strings.insert(entry.file);

        LinkReloc reloc;
        reloc.sectionIndex = static_cast<uint32_t>(image.sections.size());
        reloc.offset       = static_cast<uint32_t>(section.bytes.size());
        reloc.symbolName   = entry.symbolName;
        reloc.kind         = LinkRelocKind::Rva32;
        section.relocs.push_back(std::move(reloc));

        ByteUtils::appendLE32(section.bytes, 0); // rva, filled by the writer
        ByteUtils::appendLE32(section.bytes, entry.size);
        ByteUtils::appendLE32(section.bytes, nameOff);
        ByteUtils::appendLE32(section.bytes, fileOff);
        ByteUtils::appendLE32(section.bytes, entry.line);
    }

    ByteUtils::appendBytes(section.bytes, asByteSpan(strings.bytes));
    image.sections.push_back(std::move(section));
}

void LinkerPe::collectExports(LinkImage& image) const
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

Result LinkerPe::buildImage(LinkImage& image) const
{
    SWC_ASSERT(builder_ != nullptr);

    std::vector<CoffObject> objects;
    SWC_RESULT(readObjects(objects));

    std::vector<Archive> archives;
    SWC_RESULT(loadArchives(archives));

    SWC_RESULT(resolveSymbols(image, objects, archives));

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

Result LinkerPe::prepareLink(LinkJob& outJob)
{
    SWC_ASSERT(builder_ != nullptr);
    outJob.outputPath = builder_->artifactPath;
    outJob.buildDir   = builder_->buildDir;

    switch (builder_->compiler().buildCfg().backendKind)
    {
        case Runtime::BuildCfgBackendKind::Executable:
            outJob.output = LinkJob::Output::Executable;
            return buildImage(outJob.image);
        case Runtime::BuildCfgBackendKind::SharedLibrary:
            outJob.output = LinkJob::Output::SharedLibrary;
            return buildImage(outJob.image);
        case Runtime::BuildCfgBackendKind::StaticLibrary:
            outJob.output = LinkJob::Output::StaticLibrary;
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
