#include "pch.h"
#include "Backend/Linker/PELinker.h"
#include "Backend/Debug/DebugInfo.h"
#include "Backend/Debug/DebugRecordCollector.h"
#include "Backend/Linker/Archive.h"
#include "Backend/Linker/CoffReader.h"
#include "Backend/Micro/MachineCode.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/SourceFile.h"
#include "Main/FileSystem.h"
#include "Main/Global.h"
#include "Support/Math/Helpers.h"
#include "Support/Report/Assert.h"
#include "Support/Thread/JobManager.h"

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

    void appendAlignedBytes(ByteArray& outBytes, uint32_t& outOffset, const ByteArray& bytes)
    {
        const uint32_t alignedOffset = Math::alignUpU32(static_cast<uint32_t>(outBytes.size()), 16);
        if (outBytes.size() < alignedOffset)
            outBytes.resize(alignedOffset, std::byte{0});
        outOffset = alignedOffset;
        outBytes.append(bytes);
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

    struct ArchiveLoadItem
    {
        fs::path path;
        Archive  archive;
        bool     loaded = false;
    };

    void collectArchiveLoadItems(std::vector<ArchiveLoadItem>& outItems, const std::set<Utf8>& libNames, const std::vector<fs::path>& dirs)
    {
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

                outItems.push_back({.path = candidate});
                break;
            }
        }
    }

    Result loadArchiveItem(ArchiveLoadItem& item)
    {
        FileSystem::IoErrorInfo ioError;
        ByteArray               bytes;
        if (FileSystem::readBinaryFile(item.path, bytes, ioError) != Result::Continue)
            return Result::Continue;

        Archive    archive;
        Diagnostic diag; // a non-archive candidate is silently skipped
        if (archive.load(diag, std::move(bytes)))
        {
            item.archive = std::move(archive);
            item.loaded  = true;
        }
        return Result::Continue;
    }

    Result loadArchivesFromSearch(std::vector<Archive>& outArchives, const std::set<Utf8>& libNames, const std::vector<fs::path>& dirs)
    {
        std::vector<ArchiveLoadItem> items;
        collectArchiveLoadItems(items, libNames, dirs);
        for (ArchiveLoadItem& item : items)
        {
            SWC_RESULT(loadArchiveItem(item));
            if (item.loaded)
                outArchives.push_back(std::move(item.archive));
        }
        return Result::Continue;
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
                    section.bytes.writeLe64(patchOffset, relocation.addend);
                    break;
                case IMAGE_REL_AMD64_ADDR32NB:
                    if (patchOffset + sizeof(uint32_t) > section.bytes.size())
                        return builder_->reportError(DiagnosticId::cmd_err_link_reloc_out_of_bounds);
                    section.bytes.writeLe32(patchOffset, static_cast<uint32_t>(relocation.addend));
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

    struct DebugTableBuild
    {
        LinkSection section;
        bool        hasSection = false;
    };

    void   collectPeLibrarySearch(NativeBackendBuilder& builder, std::set<Utf8>& outLibNames, std::vector<fs::path>& outDirs);
    void   buildLinkDebugTable(NativeBackendBuilder& builder, DebugTableBuild& outDebugTable);
    Result collectLinkWin32ApplicationConfig(NativeBackendBuilder& builder, LinkWin32ApplicationConfig& outConfig);
    bool   shouldCollectLinkDebugInfo(const NativeBackendBuilder& builder);
    void   collectLinkDebugInfo(NativeBackendBuilder& builder, LinkJob& outJob);

    class LinkPrepareJobBase : public Job
    {
    public:
        explicit LinkPrepareJobBase(const TaskContext& ctx) :
            Job(ctx, JobKind::NativeLinkPrepare)
        {
        }

        Result result() const noexcept { return result_.load(std::memory_order_acquire); }

    protected:
        void setResult(const Result result) noexcept { result_.store(result, std::memory_order_release); }

    private:
        std::atomic<Result> result_ = Result::Continue;
    };

    class ArchiveLoadJob final : public LinkPrepareJobBase
    {
    public:
        ArchiveLoadJob(const TaskContext& ctx, ArchiveLoadItem& item) :
            LinkPrepareJobBase(ctx),
            item_(&item)
        {
        }

        JobResult exec() override
        {
            ctx().state().setNone();
            SWC_ASSERT(item_ != nullptr);
            setResult(loadArchiveItem(*item_));
            return JobResult::Done;
        }

    private:
        ArchiveLoadItem* item_ = nullptr;
    };

    class DebugTableJob final : public LinkPrepareJobBase
    {
    public:
        DebugTableJob(const TaskContext& ctx, NativeBackendBuilder& builder, DebugTableBuild& outDebugTable) :
            LinkPrepareJobBase(ctx),
            builder_(&builder),
            outDebugTable_(&outDebugTable)
        {
        }

        JobResult exec() override
        {
            ctx().state().setNone();
            SWC_ASSERT(builder_ != nullptr);
            SWC_ASSERT(outDebugTable_ != nullptr);
            buildLinkDebugTable(*builder_, *outDebugTable_);
            return JobResult::Done;
        }

    private:
        NativeBackendBuilder* builder_       = nullptr;
        DebugTableBuild*      outDebugTable_ = nullptr;
    };

    class StaticArchiveMemberJob final : public LinkPrepareJobBase
    {
    public:
        StaticArchiveMemberJob(const TaskContext& ctx, const NativeObjDescription& description, LinkArchiveMember& outMember) :
            LinkPrepareJobBase(ctx),
            description_(&description),
            outMember_(&outMember)
        {
        }

        JobResult exec() override
        {
            ctx().state().setNone();
            SWC_ASSERT(description_ != nullptr);
            SWC_ASSERT(outMember_ != nullptr);
            outMember_->name  = Utf8(description_->objPath.filename());
            outMember_->bytes = description_->objBytes;
            return JobResult::Done;
        }

    private:
        const NativeObjDescription* description_ = nullptr;
        LinkArchiveMember*          outMember_   = nullptr;
    };

    void collectPeLibrarySearch(NativeBackendBuilder& builder, std::set<Utf8>& outLibNames, std::vector<fs::path>& outDirs)
    {
        // Library names: every foreign-function and dependency-hook module.
        for (const Utf8& library : builder.compiler().foreignLibs())
            outLibNames.insert(normalizedLibName(library.view()));
        for (const NativeFunctionInfo& info : builder.functionInfos)
            if (info.machineCode)
                collectForeignLibs(outLibNames, *info.machineCode);
        if (builder.startup)
            collectForeignLibs(outLibNames, builder.startup->code);

        // Search directories: the SDK/MSVC library directories, then dependency link dirs and the folders
        // that hold imported-API artifacts.
        Os::WindowsToolchainPaths toolchain;
        Os::discoverWindowsToolchainPaths(toolchain);
        for (const fs::path& dir : {toolchain.vcLibPath, toolchain.sdkUmLibPath, toolchain.sdkUcrtLibPath})
            if (!dir.empty())
                outDirs.push_back(dir);

        for (const fs::path& dir : builder.compiler().importedDependencyLinkDirs())
            outDirs.push_back(dir);

        for (const SourceFile* file : builder.compiler().files())
        {
            if (!file || !file->hasFlag(FileFlagsE::ImportedApi) || !file->path().has_parent_path())
                continue;
            const fs::path parent = file->path().parent_path().lexically_normal();
            if (std::ranges::find(outDirs, parent) == outDirs.end())
                outDirs.push_back(parent);
        }
    }
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
    collectPeLibrarySearch(*builder_, outLibNames, outDirs);
}

Result PELinker::loadArchives(std::vector<Archive>& outArchives) const
{
    std::set<Utf8>        libNames;
    std::vector<fs::path> dirs;
    collectLibrarySearch(libNames, dirs);
    return loadArchivesFromSearch(outArchives, libNames, dirs);
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

            const std::span<const std::byte> memberBytes = archive.memberData(diag, memberOffset);
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
            bytes.appendCString(value.view());
            return offset;
        }

        uint32_t                           blobBase = 0;
        ByteArray                          bytes;
        std::unordered_map<Utf8, uint32_t> offsets;
    };

    struct DebugTableEntry
    {
        Utf8     symbolName;
        Utf8     name;
        Utf8     file;
        uint32_t line = 0;
        uint32_t size = 0;
    };

    void appendDebugTable(LinkImage& image, DebugTableBuild& debugTable)
    {
        if (!debugTable.hasSection)
            return;

        const uint32_t sectionIndex = static_cast<uint32_t>(image.sections.size());
        for (LinkReloc& reloc : debugTable.section.relocs)
            reloc.sectionIndex = sectionIndex;
        image.sections.push_back(std::move(debugTable.section));
        debugTable.hasSection = false;
    }

    void buildLinkDebugTable(NativeBackendBuilder& builder, DebugTableBuild& outDebugTable)
    {
        outDebugTable = {};

        std::vector<DebugTableEntry> entries;
        entries.reserve(builder.functionInfos.size());
        for (const NativeFunctionInfo& info : builder.functionInfos)
        {
            if (!info.machineCode)
                continue;

            DebugTableEntry entry;
            entry.symbolName = info.symbolName;
            entry.name       = info.debugName.empty() ? info.symbolName : info.debugName;
            entry.size       = static_cast<uint32_t>(info.machineCode->bytes.size());

            MachineCode::ResolvedDebugSourceRange resolved;
            if (info.machineCode->tryResolveDebugSourceRangeAtOffset(builder.ctx(), resolved, 0) && resolved.source.sourceFile)
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

        section.bytes.appendLe32(0x42445753u); // 'SWDB'
        section.bytes.appendLe32(1);           // version
        section.bytes.appendLe32(static_cast<uint32_t>(entries.size()));
        section.bytes.appendLe32(strings.blobBase);

        for (const DebugTableEntry& entry : entries)
        {
            const uint32_t nameOff = strings.insert(entry.name);
            const uint32_t fileOff = strings.insert(entry.file);

            LinkReloc reloc;
            reloc.offset     = static_cast<uint32_t>(section.bytes.size());
            reloc.symbolName = entry.symbolName;
            reloc.kind       = LinkRelocKind::Rva32;
            section.relocs.push_back(std::move(reloc));

            section.bytes.appendLe32(0); // rva, filled by the writer
            section.bytes.appendLe32(entry.size);
            section.bytes.appendLe32(nameOff);
            section.bytes.appendLe32(fileOff);
            section.bytes.appendLe32(entry.line);
        }

        section.bytes.append(strings.bytes);
        outDebugTable.section    = std::move(section);
        outDebugTable.hasSection = true;
    }
}

// Emits a self-contained `.swagdbg` symbol table (function name + source location per function, keyed
// by image-relative address) so the runtime can symbolize stack traces without a PDB or dbghelp. The
// function addresses are written as Rva32 relocations resolved by the PE writer.
void PELinker::buildDebugTable(LinkImage& image) const
{
    SWC_ASSERT(builder_ != nullptr);
    DebugTableBuild debugTable;
    buildLinkDebugTable(*builder_, debugTable);
    appendDebugTable(image, debugTable);
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

namespace
{
    Result collectLinkWin32ApplicationConfig(NativeBackendBuilder& builder, LinkWin32ApplicationConfig& outConfig)
    {
        outConfig                         = {};
        const Runtime::BuildCfg& buildCfg = builder.compiler().buildCfg();

        if (buildCfg.backendSubKind == Runtime::BuildCfgBackendSubKind::Default)
            outConfig.subsystem = LinkWin32Subsystem::Windows;
        else
            outConfig.subsystem = LinkWin32Subsystem::Console;

        if (buildCfg.backendKind != Runtime::BuildCfgBackendKind::Executable)
            return Result::Continue;

        outConfig.appName        = Utf8(buildCfg.resAppName);
        outConfig.appDescription = Utf8(buildCfg.resAppDescription);
        outConfig.appCompany     = Utf8(buildCfg.resAppCompany);
        outConfig.appCopyright   = Utf8(buildCfg.resAppCopyright);
        outConfig.version        = buildCfg.moduleVersion;
        outConfig.revision       = buildCfg.moduleRevision;
        outConfig.buildNum       = buildCfg.moduleBuildNum;

        const auto iconFileName = Utf8(buildCfg.resAppIcoFileName);
        if (iconFileName.empty())
            return Result::Continue;

        fs::path iconPath(iconFileName.c_str());
        if (iconPath.is_relative())
            iconPath = FileSystem::absolutePathNoThrow(iconPath);
        iconPath = iconPath.lexically_normal();

        FileSystem::IoErrorInfo ioError;
        if (FileSystem::readBinaryFile(iconPath, outConfig.iconBytes, ioError) != Result::Continue)
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_link_resource_read_failed);
            FileSystem::setDiagnosticPathAndBecause(diag, &builder.ctx(), iconPath, FileSystem::describeIoFailure(ioError));
            return builder.reportError(diag);
        }

        outConfig.iconPath = Utf8(iconPath);
        return Result::Continue;
    }
}

Result PELinker::collectWin32ApplicationConfig(LinkWin32ApplicationConfig& outConfig) const
{
    SWC_ASSERT(builder_ != nullptr);
    return collectLinkWin32ApplicationConfig(*builder_, outConfig);
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

    LinkWin32ApplicationConfig win32Config;
    SWC_RESULT(collectWin32ApplicationConfig(win32Config));
    finishImage(image, std::move(win32Config));
    return Result::Continue;
}

void PELinker::finishImage(LinkImage& image, LinkWin32ApplicationConfig&& win32Config) const
{
    SWC_ASSERT(builder_ != nullptr);

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
    image.win32        = std::move(win32Config);
}

Result PELinker::prepareImageLink(LinkJob& outJob, const LinkJob::Output output) const
{
    outJob.output = output;
    if (canPrepareLinkInParallel())
        return prepareImageLinkParallel(outJob);

    SWC_RESULT(buildImage(outJob.image));
    collectDebugInfo(outJob);
    return Result::Continue;
}

Result PELinker::prepareImageLinkParallel(LinkJob& outJob) const
{
    SWC_ASSERT(builder_ != nullptr);

    JobManager&       jobMgr   = builder_->ctx().global().jobMgr();
    const JobClientId clientId = jobMgr.newClientId();

    std::set<Utf8>        libNames;
    std::vector<fs::path> dirs;
    collectLibrarySearch(libNames, dirs);
    std::vector<ArchiveLoadItem> archiveItems;
    collectArchiveLoadItems(archiveItems, libNames, dirs);

    std::vector<std::unique_ptr<LinkPrepareJobBase>> jobs;
    jobs.reserve(archiveItems.size() + 1);
    auto enqueueJob = [&](std::unique_ptr<LinkPrepareJobBase> job) {
        LinkPrepareJobBase& ref = *job;
        jobs.push_back(std::move(job));
        jobMgr.enqueue(ref, JobPriority::Normal, clientId);
    };

    for (ArchiveLoadItem& item : archiveItems)
        enqueueJob(std::make_unique<ArchiveLoadJob>(builder_->ctx(), item));

    SWC_RESULT(buildNativeImage(outJob.image));

    DebugTableBuild debugTable;
    enqueueJob(std::make_unique<DebugTableJob>(builder_->ctx(), *builder_, debugTable));

    LinkWin32ApplicationConfig win32Config;
    SWC_RESULT(collectWin32ApplicationConfig(win32Config));

    jobMgr.waitAll(clientId);
    for (const std::unique_ptr<LinkPrepareJobBase>& job : jobs)
        SWC_RESULT(job->result());

    std::vector<Archive> archives;
    archives.reserve(archiveItems.size());
    for (ArchiveLoadItem& item : archiveItems)
        if (item.loaded)
            archives.push_back(std::move(item.archive));

    SWC_RESULT(resolveSymbols(outJob.image, archives));
    appendDebugTable(outJob.image, debugTable);
    finishImage(outJob.image, std::move(win32Config));
    collectDebugInfo(outJob);
    return Result::Continue;
}

namespace
{
    // Normalises a source path the way debuggers expect it in CodeView line tables.
    Utf8 debugSourcePath(const fs::path& path)
    {
        fs::path normalized = path.lexically_normal();
        normalized.make_preferred();
        return {normalized.string()};
    }

    bool shouldCollectLinkDebugInfo(const NativeBackendBuilder& builder)
    {
        return builder.compiler().buildCfg().backend.debugInfo && !builder.pdbPath.empty();
    }

    // Lowers the backend's per-function debug state (names, source line tables, types, locals and global
    // data) into the self-contained LinkDebugInfo the image writer turns into a PDB.
    void collectLinkDebugInfo(NativeBackendBuilder& builder, LinkJob& outJob)
    {
        if (!shouldCollectLinkDebugInfo(builder))
            return;

        LinkDebugInfo& dbg = outJob.debugInfo;
        dbg.enabled        = true;
        outJob.pdbPath     = builder.pdbPath;

        // Gather the backend debug records (shared with the COFF object writer), then lower their types.
        std::vector<const NativeFunctionInfo*> functionPtrs;
        functionPtrs.reserve(builder.functionInfos.size());
        for (const NativeFunctionInfo& info : builder.functionInfos)
            functionPtrs.push_back(&info);

        CollectedDebugRecords collected;
        collectDebugRecords(builder, functionPtrs, builder.startup.get(), true, collected);

        // Mirror the COFF object split as PDB compilands: each function's owning object file (its codegen
        // job) becomes a module named after that .obj. Visual Studio expects this per-object compiland
        // layout; the previous source-file-sized ones (with the image itself as module 0) confused its
        // module model.
        dbg.objectNames.reserve(builder.objectDescriptions.size());
        for (const NativeObjDescription& obj : builder.objectDescriptions)
        {
            // Use native (backslash) separators as expected by Windows PDB consumers.
            auto objName = Utf8(obj.objPath);
            std::ranges::replace(objName, '/', '\\');
            dbg.objectNames.push_back(std::move(objName));
        }

        std::unordered_map<std::string_view, uint32_t> objIndexBySymbol;
        objIndexBySymbol.reserve(builder.functionInfos.size() + 1);
        for (const NativeFunctionInfo& info : builder.functionInfos)
            objIndexBySymbol.insert_or_assign(info.symbolName.view(), info.jobIndex);
        if (builder.startup)
            objIndexBySymbol.insert_or_assign(builder.startup->symbolName.view(), 0u);

        const DebugInfoObjectRequest request = {
            .ctx        = &builder.ctx(),
            .targetOs   = builder.ctx().cmdLine().targetOs,
            .objectPath = builder.artifactPath,
            .functions  = collected.functions,
            .globals    = collected.globals,
            .constants  = collected.constants,
        };
        DebugInfoPdbResult pdbTypes;
        DebugInfo::buildPdbInfo(request, pdbTypes);
        dbg.tpiRecords     = std::move(pdbTypes.tpiRecords);
        dbg.ipiRecords     = std::move(pdbTypes.ipiRecords);
        dbg.tpiIndexEnd    = pdbTypes.tpiIndexEnd;
        dbg.ipiIndexEnd    = pdbTypes.ipiIndexEnd;
        dbg.buildInfoIndex = pdbTypes.buildInfoIndex;

        std::unordered_map<Utf8, uint32_t> fileIndices;
        const auto                         fileIndexFor = [&](const Utf8& path, const SourceFile* sourceFile) {
            if (const auto it = fileIndices.find(path); it != fileIndices.end())
                return it->second;
            const auto    index = static_cast<uint32_t>(dbg.files.size());
            LinkDebugFile entry;
            entry.path = path;
            if (sourceFile)
            {
                const std::array<uint8_t, 32> hash = DebugInfo::sourceFileChecksum(builder.ctx(), *sourceFile);
                entry.checksum.assign(hash.begin(), hash.end());
                entry.checksumKind = 3; // CV_SourceChksum_SHA256
            }
            dbg.files.push_back(std::move(entry));
            fileIndices.emplace(path, index);
            return index;
        };

        dbg.functions.reserve(collected.functions.size());
        for (size_t i = 0; i < collected.functions.size(); ++i)
        {
            const DebugInfoFunctionRecord& record = collected.functions[i];
            if (!record.machineCode)
                continue;

            LinkDebugFunction fn;
            fn.symbolName  = record.symbolName;
            fn.displayName = record.debugName.empty() ? record.symbolName : record.debugName;
            fn.codeSize    = static_cast<uint32_t>(record.machineCode->bytes.size());
            if (const auto objIt = objIndexBySymbol.find(record.symbolName.view()); objIt != objIndexBySymbol.end())
                fn.objIndex = objIt->second;
            fn.frameSize = record.frameSize;
            if (record.sourceFile)
            {
                const Utf8 path     = debugSourcePath(record.sourceFile->path());
                fn.primaryFileIndex = fileIndexFor(path, record.sourceFile);
            }

            if (i < pdbTypes.functions.size())
            {
                const DebugInfoPdbFunction& fnTypes = pdbTypes.functions[i];
                fn.procTypeIndex                    = fnTypes.procTypeIndex;
                fn.frameProcFlags                   = fnTypes.frameFlags;
                fn.frameToCodeReg                   = fnTypes.frameReg;
                for (const DebugInfoPdbLocal& local : fnTypes.locals)
                    fn.locals.push_back({.name = local.name, .typeIndex = local.typeIndex, .frameOffset = local.frameOffset, .cvRegister = local.cvRegister, .isParam = local.isParam});
            }

            // Build the line blocks as contiguous source-file runs, dropping consecutive duplicate lines.
            // CodeView consumers expect offsets inside a block to be ordered; macro-expanded code can switch
            // source files and later return to the original file, so grouping all lines by file breaks DIA/VS.
            size_t   currentBlock = std::numeric_limits<size_t>::max();
            uint32_t currentFile  = std::numeric_limits<uint32_t>::max();
            for (const auto& range : record.machineCode->debugSourceRanges)
            {
                if (!range.debugSourceInfo.isStepVisible())
                    continue;

                MachineCode::ResolvedDebugSourceRange resolved;
                if (!MachineCode::tryResolveDebugSourceRange(builder.ctx(), resolved, range) || !resolved.source.codeRange.line)
                    continue;
                if (!resolved.source.sourceFile)
                    continue;

                const Utf8     path = debugSourcePath(resolved.source.sourceFile->path());
                const uint32_t file = fileIndexFor(path, resolved.source.sourceFile);

                if (currentBlock == std::numeric_limits<size_t>::max() || currentFile != file)
                {
                    currentBlock = fn.lineBlocks.size();
                    fn.lineBlocks.emplace_back();
                    fn.lineBlocks.back().fileIndex = file;
                    currentFile                    = file;
                }

                LinkDebugLineBlock& block = fn.lineBlocks[currentBlock];
                const uint32_t      line  = std::min<uint32_t>(resolved.source.codeRange.line, 0x00FFFFFFu);
                if (!block.lines.empty() && block.lines.back() == line)
                    continue;
                block.codeOffsets.push_back(resolved.debugRange->codeStartOffset);
                block.lines.push_back(line);
            }

            // The prologue is emitted as non-step-visible code, so the first step-visible
            // range (and hence the first line record) starts past the function entry. That
            // leaves the entry point and prologue without any source mapping, so a breakpoint
            // at the function start or a sample landing in the prologue resolves to nothing.
            // Mirror MSVC by extending the function's first line down to code offset 0.
            size_t prologueBlock = std::numeric_limits<size_t>::max();
            if (fn.primaryFileIndex != std::numeric_limits<uint32_t>::max())
            {
                for (size_t blockIndex = 0; blockIndex < fn.lineBlocks.size(); ++blockIndex)
                {
                    if (fn.lineBlocks[blockIndex].fileIndex != fn.primaryFileIndex)
                        continue;
                    prologueBlock = blockIndex;
                    break;
                }
            }
            if (prologueBlock == std::numeric_limits<size_t>::max() && !fn.lineBlocks.empty())
                prologueBlock = 0;
            if (prologueBlock != std::numeric_limits<size_t>::max() && !fn.lineBlocks[prologueBlock].codeOffsets.empty())
                fn.lineBlocks[prologueBlock].codeOffsets.front() = 0;

            dbg.functions.push_back(std::move(fn));
        }

        dbg.globals.reserve(collected.globals.size());
        for (size_t i = 0; i < collected.globals.size(); ++i)
        {
            const DebugInfoDataRecord& data = collected.globals[i];
            LinkDebugGlobal            g;
            g.sectionName   = data.sectionName;
            g.sectionOffset = data.symbolOffset;
            g.displayName   = data.name.empty() ? data.symbolName : data.name;
            g.typeIndex     = i < pdbTypes.globalTypes.size() ? pdbTypes.globalTypes[i] : 0;
            g.isPublic      = data.isGlobal;
            dbg.globals.push_back(std::move(g));
        }

        for (const DebugInfoPdbUdt& udt : pdbTypes.udts)
            dbg.udts.push_back({.name = udt.name, .typeIndex = udt.typeIndex});
    }
}

void PELinker::collectDebugInfo(LinkJob& outJob) const
{
    SWC_ASSERT(builder_ != nullptr);
    collectLinkDebugInfo(*builder_, outJob);
}

bool PELinker::canPrepareLinkInParallel() const
{
    SWC_ASSERT(builder_ != nullptr);
    return builder_->ctx().global().jobMgr().numWorkers() != 0;
}

bool PELinker::shouldCollectDebugInfo() const
{
    SWC_ASSERT(builder_ != nullptr);
    return shouldCollectLinkDebugInfo(*builder_);
}

Result PELinker::prepareStaticLibraryLink(LinkJob& outJob) const
{
    SWC_ASSERT(builder_ != nullptr);

    outJob.output = LinkJob::Output::StaticLibrary;
    outJob.archiveMembers.resize(builder_->objectDescriptions.size());
    if (!canPrepareLinkInParallel() || builder_->objectDescriptions.size() <= 1)
    {
        for (uint32_t i = 0; i < builder_->objectDescriptions.size(); ++i)
        {
            const NativeObjDescription& description = builder_->objectDescriptions[i];
            outJob.archiveMembers[i]                = {.name = Utf8(description.objPath.filename()), .bytes = description.objBytes};
        }
        return Result::Continue;
    }

    JobManager&       jobMgr   = builder_->ctx().global().jobMgr();
    const JobClientId clientId = jobMgr.newClientId();

    std::vector<std::unique_ptr<StaticArchiveMemberJob>> jobs;
    jobs.reserve(builder_->objectDescriptions.size());
    for (uint32_t i = 0; i < builder_->objectDescriptions.size(); ++i)
    {
        auto                    job = std::make_unique<StaticArchiveMemberJob>(builder_->ctx(), builder_->objectDescriptions[i], outJob.archiveMembers[i]);
        StaticArchiveMemberJob& ref = *job;
        jobs.push_back(std::move(job));
        jobMgr.enqueue(ref, JobPriority::Normal, clientId);
    }

    jobMgr.waitAll(clientId);
    for (const std::unique_ptr<StaticArchiveMemberJob>& job : jobs)
        SWC_RESULT(job->result());
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
            return prepareImageLink(outJob, LinkJob::Output::Executable);
        case Runtime::BuildCfgBackendKind::SharedLibrary:
            return prepareImageLink(outJob, LinkJob::Output::SharedLibrary);
        case Runtime::BuildCfgBackendKind::StaticLibrary:
            return prepareStaticLibraryLink(outJob);
        case Runtime::BuildCfgBackendKind::Export:
        case Runtime::BuildCfgBackendKind::None:
            SWC_UNREACHABLE();
    }

    SWC_UNREACHABLE();
}

SWC_END_NAMESPACE();
