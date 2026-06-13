#include "pch.h"
#include "Backend/Linker/PELinker.h"
#include "Backend/Debug/DebugInfo.h"
#include "Backend/Linker/Archive.h"
#include "Backend/Linker/CoffReader.h"
#include "Backend/Micro/MachineCode.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/SourceFile.h"
#include "Main/FileSystem.h"
#include "Support/Core/ByteUtils.h"
#include "Support/Math/Helpers.h"

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

    bool isDebugSectionName(const Utf8& name)
    {
        return name.view().starts_with(".debug");
    }

    uint32_t alignmentFromCharacteristics(const uint32_t characteristics)
    {
        const uint32_t field = (characteristics & 0x00F00000u) >> 20;
        if (field == 0)
            return 1;
        return 1u << (field - 1);
    }

    EnumFlags<LinkSectionFlagsE> flagsFromCharacteristics(const uint32_t characteristics)
    {
        EnumFlags<LinkSectionFlagsE> flags;
        if (characteristics & IMAGE_SCN_CNT_CODE)
            flags.add(LinkSectionFlagsE::Code);
        if (characteristics & IMAGE_SCN_MEM_EXECUTE)
            flags.add(LinkSectionFlagsE::Execute);
        if (characteristics & IMAGE_SCN_MEM_READ)
            flags.add(LinkSectionFlagsE::Read);
        if (characteristics & IMAGE_SCN_MEM_WRITE)
            flags.add(LinkSectionFlagsE::Write);
        if (characteristics & IMAGE_SCN_CNT_UNINITIALIZED_DATA)
            flags.add(LinkSectionFlagsE::Uninit);
        return flags;
    }

    bool linkRelocKindFromNativeType(LinkRelocKind& outKind, const uint16_t type)
    {
        switch (type)
        {
            case IMAGE_REL_AMD64_ADDR64:
                outKind = LinkRelocKind::Abs64;
                return true;
            case IMAGE_REL_AMD64_ADDR32NB:
                outKind = LinkRelocKind::Rva32;
                return true;
            default:
                return false;
        }
    }

    void appendAlignedBytes(std::vector<std::byte>& outBytes, uint32_t& outOffset, const std::vector<std::byte>& bytes)
    {
        const uint32_t alignedOffset = Math::alignUpU32(static_cast<uint32_t>(outBytes.size()), 16);
        if (outBytes.size() < alignedOffset)
            outBytes.resize(alignedOffset, std::byte{0});
        outOffset = alignedOffset;
        outBytes.insert(outBytes.end(), bytes.begin(), bytes.end());
    }

    void collectDefined(std::unordered_set<Utf8>& outDefined, const LinkImage& image)
    {
        for (const LinkSymbol& symbol : image.symbols)
            outDefined.insert(symbol.name);
    }

    void collectUndefined(std::unordered_set<Utf8>& outUndefined, const CoffObject& object, const std::unordered_set<Utf8>& defined)
    {
        for (const CoffInputSection& section : object.sections)
        {
            if (isDebugSectionName(section.name))
                continue;
            for (const CoffInputReloc& reloc : section.relocs)
            {
                if (!defined.contains(reloc.symbolName))
                    outUndefined.insert(reloc.symbolName);
            }
        }
    }

    void collectUndefined(std::unordered_set<Utf8>& outUndefined, const LinkImage& image, const std::unordered_set<Utf8>& defined)
    {
        for (const LinkSection& section : image.sections)
        {
            if (isDebugSectionName(section.name))
                continue;
            for (const LinkReloc& reloc : section.relocs)
            {
                if (!defined.contains(reloc.symbolName))
                    outUndefined.insert(reloc.symbolName);
            }
        }
    }

    struct SectionPlacement
    {
        uint32_t index = 0;
        uint32_t base  = 0;
        bool     valid = false;
    };

    class NativeImageLowering
    {
    public:
        NativeImageLowering(NativeBackendBuilder& builder, LinkImage& image) :
            builder_(&builder),
            image_(&image)
        {
            for (uint32_t i = 0; i < image.sections.size(); ++i)
                sectionByName_[image.sections[i].name] = i;
            for (const LinkSymbol& symbol : image.symbols)
                definedNames_.insert(symbol.name);
        }

        Result appendDescription(const NativeObjDescription& description)
        {
            SWC_RESULT(appendTextSection(description));
            if (description.includeData)
                SWC_RESULT(appendDataSections());
            return appendUnwindSections(description);
        }

    private:
        Result appendTextSection(const NativeObjDescription& description)
        {
            NativeSectionData textSection;
            textSection.name            = ".text";
            textSection.characteristics = IMAGE_SCN_CNT_CODE | IMAGE_SCN_MEM_EXECUTE | IMAGE_SCN_MEM_READ | IMAGE_SCN_ALIGN_16BYTES;

            if (description.startup)
                appendAlignedBytes(textSection.bytes, description.startup->textOffset, description.startup->code.bytes);
            for (NativeFunctionInfo* info : description.functions)
                appendAlignedBytes(textSection.bytes, info->textOffset, info->machineCode->bytes);

            if (description.startup)
                SWC_RESULT(appendCodeRelocations(textSection, description.startup->textOffset, description.startup->debugName, description.startup->code, description.allowUnresolvedSymbols));
            for (const NativeFunctionInfo* info : description.functions)
                SWC_RESULT(appendCodeRelocations(textSection, info->textOffset, info->debugName, *info->machineCode, description.allowUnresolvedSymbols));

            SectionPlacement placement;
            SWC_RESULT(appendNativeSection(placement, textSection));
            if (description.startup)
                addSymbol(description.startup->symbolName, placement.index, placement.base + description.startup->textOffset);
            for (const NativeFunctionInfo* info : description.functions)
                addSymbol(info->symbolName, placement.index, placement.base + info->textOffset);
            return Result::Continue;
        }

        Result appendCodeRelocations(NativeSectionData& textSection, const uint32_t functionOffset, const Utf8& ownerName, const MachineCode& code, const bool allowUnresolvedSymbols) const
        {
            NativeCodeRelocationTarget target;
            target.bytes                  = &textSection.bytes;
            target.relocations            = &textSection.relocations;
            target.functionOffset         = functionOffset;
            target.allowUnresolvedSymbols = allowUnresolvedSymbols;
            for (const MicroRelocation& relocation : code.codeRelocations)
                SWC_RESULT(builder_->appendCodeRelocation(target, ownerName, relocation));
            return Result::Continue;
        }

        Result appendDataSections()
        {
            SWC_ASSERT(builder_ != nullptr);
            if (!builder_->mergedRData.bytes.empty())
                SWC_RESULT(appendDataSection(builder_->mergedRData, nativeScopedSectionBaseSymbol(builder_->compiler(), K_R_DATA_BASE_SYMBOL)));
            if (!builder_->mergedData.bytes.empty())
                SWC_RESULT(appendDataSection(builder_->mergedData, nativeScopedSectionBaseSymbol(builder_->compiler(), K_DATA_BASE_SYMBOL)));
            if (builder_->mergedBss.bss)
                SWC_RESULT(appendDataSection(builder_->mergedBss, nativeScopedSectionBaseSymbol(builder_->compiler(), K_BSS_BASE_SYMBOL)));
            return Result::Continue;
        }

        Result appendDataSection(const NativeSectionData& section, const Utf8& baseSymbolName)
        {
            SectionPlacement placement;
            SWC_RESULT(appendNativeSection(placement, section));
            addSymbol(baseSymbolName, placement.index, placement.base);
            return Result::Continue;
        }

        Result appendUnwindSections(const NativeObjDescription& description)
        {
            std::vector<DebugInfoFunctionRecord> debugFunctions;
            debugFunctions.reserve(description.functions.size() + (description.startup ? 1u : 0u));

            if (description.startup)
                debugFunctions.push_back({.symbolName = description.startup->symbolName, .debugName = description.startup->debugName, .returnTypeRef = TypeRef::invalid(), .machineCode = &description.startup->code});
            for (const NativeFunctionInfo* info : description.functions)
                debugFunctions.push_back({.symbolName = info->symbolName, .debugName = info->debugName, .returnTypeRef = TypeRef::invalid(), .machineCode = info->machineCode});

            DebugInfoObjectResult        debugInfoResult;
            const DebugInfoObjectRequest debugInfoRequest = {
                .ctx          = &builder_->ctx(),
                .targetOs     = builder_->ctx().cmdLine().targetOs,
                .objectPath   = description.objPath,
                .functions    = debugFunctions,
                .emitCodeView = false,
            };
            SWC_RESULT(DebugInfo::buildObject(debugInfoRequest, debugInfoResult));

            std::unordered_map<Utf8, SectionPlacement> placements;
            for (const NativeSectionData& section : debugInfoResult.sections)
            {
                if (isDebugSectionName(section.name))
                    continue;

                SectionPlacement placement;
                SWC_RESULT(appendNativeSection(placement, section));
                placements.emplace(section.name, placement);
            }

            for (const DebugInfoDefinedSymbol& symbol : debugInfoResult.symbols)
            {
                const auto it = placements.find(symbol.sectionName);
                SWC_ASSERT(it != placements.end());
                if (it == placements.end())
                    continue;

                addSymbol(symbol.name, it->second.index, it->second.base + symbol.value);
            }

            return Result::Continue;
        }

        Result appendNativeSection(SectionPlacement& outPlacement, const NativeSectionData& section)
        {
            outPlacement = {};
            if (isDebugSectionName(section.name))
                return Result::Continue;

            uint32_t   sectionIndex = 0;
            const auto it           = sectionByName_.find(section.name);
            if (it == sectionByName_.end())
            {
                LinkSection linkSection;
                linkSection.name  = section.name;
                linkSection.align = 1;
                sectionIndex      = static_cast<uint32_t>(image_->sections.size());
                image_->sections.push_back(std::move(linkSection));
                sectionByName_.emplace(section.name, sectionIndex);
            }
            else
            {
                sectionIndex = it->second;
            }

            LinkSection&   linkSection = image_->sections[sectionIndex];
            const uint32_t align       = alignmentFromCharacteristics(section.characteristics);
            linkSection.align          = std::max(linkSection.align, align);
            linkSection.flags.add(flagsFromCharacteristics(section.characteristics));

            uint32_t base = 0;
            if (section.bss)
            {
                linkSection.bssSize = Math::alignUpU32(linkSection.bssSize, align);
                base                = linkSection.bssSize;
                linkSection.bssSize += section.bssSize;
                linkSection.flags.add(LinkSectionFlagsE::Uninit);
            }
            else
            {
                base = Math::alignUpU32(static_cast<uint32_t>(linkSection.bytes.size()), align);
                linkSection.bytes.resize(base, std::byte{0});
                linkSection.bytes.insert(linkSection.bytes.end(), section.bytes.begin(), section.bytes.end());
            }

            outPlacement.index = sectionIndex;
            outPlacement.base  = base;
            outPlacement.valid = true;

            for (const NativeSectionRelocation& relocation : section.relocations)
                SWC_RESULT(appendRelocation(sectionIndex, base, section.name, relocation));
            return Result::Continue;
        }

        Result appendRelocation(const uint32_t sectionIndex, const uint32_t base, const Utf8& sectionName, const NativeSectionRelocation& relocation) const
        {
            LinkRelocKind kind;
            if (!linkRelocKindFromNativeType(kind, relocation.type))
            {
                Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_link_coff_unsupported_reloc);
                diag.addArgument(Diagnostic::ARG_VALUE, std::to_string(relocation.type));
                diag.addArgument(Diagnostic::ARG_TARGET, sectionName);
                return builder_->reportError(diag);
            }

            LinkSection&   section     = image_->sections[sectionIndex];
            const uint32_t patchOffset = base + relocation.offset;
            switch (relocation.type)
            {
                case IMAGE_REL_AMD64_ADDR64:
                    if (patchOffset + sizeof(uint64_t) > section.bytes.size())
                        return builder_->reportError(DiagnosticId::cmd_err_link_reloc_out_of_bounds);
                    ByteUtils::writeLe64(section.bytes, patchOffset, relocation.addend);
                    break;
                case IMAGE_REL_AMD64_ADDR32NB:
                    if (patchOffset + sizeof(uint32_t) > section.bytes.size())
                        return builder_->reportError(DiagnosticId::cmd_err_link_reloc_out_of_bounds);
                    ByteUtils::writeLe32(section.bytes, patchOffset, static_cast<uint32_t>(relocation.addend));
                    break;
                default:
                    SWC_UNREACHABLE();
            }

            LinkReloc linkReloc;
            linkReloc.sectionIndex = sectionIndex;
            linkReloc.offset       = patchOffset;
            linkReloc.symbolName   = relocation.symbolName;
            linkReloc.kind         = kind;
            section.relocs.push_back(std::move(linkReloc));
            return Result::Continue;
        }

        void addSymbol(const Utf8& name, const uint32_t sectionIndex, const uint32_t value)
        {
            if (!definedNames_.insert(name).second)
                return;

            LinkSymbol symbol;
            symbol.name         = name;
            symbol.sectionIndex = sectionIndex;
            symbol.value        = value;
            image_->symbols.push_back(std::move(symbol));
        }

        NativeBackendBuilder*              builder_ = nullptr;
        LinkImage*                         image_   = nullptr;
        std::unordered_map<Utf8, uint32_t> sectionByName_;
        std::unordered_set<Utf8>           definedNames_;
    };
}

PELinker::PELinker(NativeBackendBuilder& builder) :
    Linker(builder)
{
}

Result PELinker::buildNativeImage(LinkImage& image) const
{
    SWC_ASSERT(builder_ != nullptr);
    NativeImageLowering lowering(*builder_, image);
    for (const NativeObjDescription& description : builder_->objectDescriptions)
        SWC_RESULT(lowering.appendDescription(description));

    return Result::Continue;
}

void PELinker::collectLibrarySearch(std::set<Utf8>& outLibNames, std::vector<fs::path>& outDirs) const
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

Result PELinker::loadArchives(std::vector<Archive>& outArchives) const
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

            Archive    archive;
            Diagnostic diag; // a non-archive candidate is silently skipped
            if (archive.load(diag, std::move(bytes)))
                outArchives.push_back(std::move(archive));
            break;
        }
    }

    return Result::Continue;
}

Result PELinker::resolveSymbols(LinkImage& image, std::vector<Archive>& archives) const
{
    std::unordered_set<Utf8> defined;
    collectDefined(defined, image);

    std::unordered_set<Utf8> undefined;
    collectUndefined(undefined, image, defined);

    std::unordered_set<Utf8> imported;
    std::vector<CoffObject>  pulledObjects;
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

            Diagnostic    diag; // local decode failures fall through to the next archive
            ArchiveImport archiveImport;
            if (archive.tryReadImport(archiveImport, diag, memberOffset))
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

            const ByteSpan memberBytes = archive.memberData(diag, memberOffset);
            if (memberBytes.empty())
                continue;

            CoffObject pulled;
            if (!readCoffObject(pulled, diag, memberBytes))
                continue;

            for (const CoffInputSymbol& sym : pulled.definedSymbols)
                defined.insert(sym.name);
            std::unordered_set<Utf8> newUndefined;
            collectUndefined(newUndefined, pulled, defined);
            for (const Utf8& u : newUndefined)
                if (!imported.contains(u))
                    worklist.push_back(u);

            pulledObjects.push_back(std::move(pulled));
            break;
        }
    }

    Diagnostic diag;
    if (!mergeCoffObjectsIntoImage(image, diag, pulledObjects))
        return builder_->reportError(diag);

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
void PELinker::buildDebugTable(LinkImage& image) const
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

    ByteUtils::appendLe32(section.bytes, 0x42445753u); // 'SWDB'
    ByteUtils::appendLe32(section.bytes, 1);           // version
    ByteUtils::appendLe32(section.bytes, static_cast<uint32_t>(entries.size()));
    ByteUtils::appendLe32(section.bytes, strings.blobBase);

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

        ByteUtils::appendLe32(section.bytes, 0); // rva, filled by the writer
        ByteUtils::appendLe32(section.bytes, entry.size);
        ByteUtils::appendLe32(section.bytes, nameOff);
        ByteUtils::appendLe32(section.bytes, fileOff);
        ByteUtils::appendLe32(section.bytes, entry.line);
    }

    ByteUtils::appendBytes(section.bytes, asByteSpan(strings.bytes));
    image.sections.push_back(std::move(section));
}

void PELinker::collectExports(LinkImage& image) const
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

Result PELinker::buildImage(LinkImage& image) const
{
    SWC_ASSERT(builder_ != nullptr);

    SWC_RESULT(buildNativeImage(image));

    std::vector<Archive> archives;
    SWC_RESULT(loadArchives(archives));

    SWC_RESULT(resolveSymbols(image, archives));

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

Result PELinker::prepareLink(LinkJob& outJob)
{
    SWC_ASSERT(builder_ != nullptr);
    outJob.outputPath = builder_->artifactPath;
    outJob.buildDir   = builder_->buildDir;
    outJob.targetOs   = builder_->ctx().cmdLine().targetOs;

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
            outJob.archiveMembers.reserve(builder_->objectDescriptions.size());
            for (const NativeObjDescription& description : builder_->objectDescriptions)
                outJob.archiveMembers.push_back({.name = Utf8(description.objPath.filename()), .bytes = description.objBytes});
            return Result::Continue;
        case Runtime::BuildCfgBackendKind::Export:
        case Runtime::BuildCfgBackendKind::None:
            SWC_UNREACHABLE();
    }

    SWC_UNREACHABLE();
}

SWC_END_NAMESPACE();
