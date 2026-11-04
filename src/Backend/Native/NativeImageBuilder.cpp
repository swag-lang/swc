#include "pch.h"
#include "Backend/Native/NativeImageBuilder.h"
#include "Backend/Debug/DebugInfo.h"
#include "Backend/Debug/DebugRecordCollector.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/SectionProperties.COFF.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Support/Math/Helpers.h"
#include "Support/Report/Assert.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct SectionPlacement
    {
        uint32_t index = 0;
        uint32_t base  = 0;
        bool     valid = false;
    };

    // What one object description contributes to the image, built without touching it.
    struct NativeImageDescriptionSections
    {
        NativeSectionData     textSection;
        DebugInfoObjectResult unwind;
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

        // Reads only the description and the builder, so descriptions can be built in parallel.
        Result buildDescription(NativeImageDescriptionSections& out, const NativeObjDescription& description) const
        {
            std::vector<DebugInfoFunctionRecord> debugFunctions;
            debugFunctions.reserve(description.functions.size() + (description.startup ? 1u : 0u));
            SWC_RESULT(buildTextSection(out.textSection, description, debugFunctions));
            return buildUnwindSections(out.unwind, description, debugFunctions);
        }

        // Places a built description; the image depends on the order descriptions are placed in.
        Result placeDescription(NativeImageDescriptionSections& sections, const NativeObjDescription& description)
        {
            SWC_RESULT(placeTextSection(std::move(sections.textSection), description));
            if (description.includeMergedRData && !builder_->mergedRData.bytes.empty())
                SWC_RESULT(appendDataSection(builder_->mergedRData, builder_->scopedSymbolNames().rdataBase));
            for (uint32_t index = 0; index < description.rdataAllocationCount; ++index)
            {
                const auto& allocation = builder_->rdataAllocations[description.rdataAllocationIndex + index];
                NativeSectionData section;
                SWC_RESULT(builder_->buildRDataAllocationSection(section, allocation));
                SWC_RESULT(appendDataSection(section, builder_->rdataAllocationSymbol(allocation)));
            }
            if (description.includeData)
                SWC_RESULT(appendDataSections(description.splitRDataReferences));

            return placeUnwindSections(sections.unwind);
        }

    private:
        Result buildTextSection(NativeSectionData& textSection, const NativeObjDescription& description, std::vector<DebugInfoFunctionRecord>& debugFunctions) const
        {
            textSection.name            = ".text";
            textSection.characteristics = K_NATIVE_TEXT_SECTION_COFF_CHARACTERISTICS;

            if (description.startup)
            {
                textSection.bytes.appendAligned(description.startup->textOffset, description.startup->code.bytes, description.startup->code.codeAlignment);
                SWC_RESULT(appendCodeRelocations(textSection, description.startup->textOffset, description.startup->debugName, description.startup->code, description.allowUnresolvedSymbols, description.splitRDataReferences));
                debugFunctions.push_back({.symbolName = description.startup->symbolName, .debugName = description.startup->debugName, .returnTypeRef = TypeRef::invalid(), .machineCode = &description.startup->code});
            }
            for (NativeFunctionInfo* info : description.functions)
            {
                textSection.bytes.appendAligned(info->textOffset, info->machineCode->bytes, info->machineCode->codeAlignment);
                SWC_RESULT(appendCodeRelocations(textSection, info->textOffset, info->debugName, *info->machineCode, description.allowUnresolvedSymbols, description.splitRDataReferences));
                debugFunctions.push_back({.symbolName = info->symbolName, .debugName = info->debugName, .returnTypeRef = TypeRef::invalid(), .machineCode = info->machineCode});
            }

            return Result::Continue;
        }

        Result placeTextSection(NativeSectionData&& textSection, const NativeObjDescription& description)
        {
            SectionPlacement placement;
            SWC_RESULT(appendNativeSection(placement, std::move(textSection)));

            if (description.startup)
                addSymbol(description.startup->symbolName, placement.index, placement.base + description.startup->textOffset);
            for (const NativeFunctionInfo* info : description.functions)
                addSymbol(info->symbolName, placement.index, placement.base + info->textOffset);

            return Result::Continue;
        }

        Result appendCodeRelocations(NativeSectionData& textSection, const uint32_t functionOffset, const Utf8& ownerName, const MachineCode& code, const bool allowUnresolvedSymbols, const bool splitRDataReferences) const
        {
            NativeCodeRelocationTarget target;
            target.bytes                  = &textSection.bytes;
            target.relocations            = &textSection.relocations;
            target.functionOffset         = functionOffset;
            target.allowUnresolvedSymbols = allowUnresolvedSymbols;
            target.splitRDataReferences = splitRDataReferences;

            for (const MicroRelocation& relocation : code.codeRelocations)
                SWC_RESULT(builder_->appendCodeRelocation(target, ownerName, relocation));

            return Result::Continue;
        }

        Result appendDataSections(bool splitRDataReferences)
        {
            SWC_ASSERT(builder_ != nullptr);
            if (!builder_->mergedData.bytes.empty())
            {
                if (splitRDataReferences)
                {
                    NativeSectionData data = builder_->mergedData;
                    SWC_RESULT(builder_->remapRDataReferences(data));
                    SWC_RESULT(appendDataSection(data, builder_->scopedSymbolNames().dataBase));
                }
                else
                    SWC_RESULT(appendDataSection(builder_->mergedData, builder_->scopedSymbolNames().dataBase));
            }
            if (builder_->mergedBss.bss)
                SWC_RESULT(appendDataSection(builder_->mergedBss, builder_->scopedSymbolNames().bssBase));

            return Result::Continue;
        }

        Result appendDataSection(const NativeSectionData& section, const Utf8& baseSymbolName)
        {
            SectionPlacement placement;
            SWC_RESULT(appendNativeSection(placement, section));
            addSymbol(baseSymbolName, placement.index, placement.base);
            return Result::Continue;
        }

        Result buildUnwindSections(DebugInfoObjectResult& debugInfoResult, const NativeObjDescription& description, const std::vector<DebugInfoFunctionRecord>& debugFunctions) const
        {
            CollectedDebugRecords records;
            const bool            emitDwarf = builder_->ctx().cmdLine().targetOs == Runtime::TargetOs::Linux && builder_->compiler().buildCfg().backend.debugInfo;
            if (emitDwarf)
                collectDebugRecords(*builder_, description.functions, description.startup, false, records);
            const DebugInfoObjectRequest debugInfoRequest = {
                .ctx             = &builder_->ctx(),
                .targetOs        = builder_->ctx().cmdLine().targetOs,
                .objectPath      = description.objPath,
                .objectIndex     = description.index,
                .symbolScopeHash = builder_->scopedSymbolNames().scopeHash,
                .functions       = emitDwarf ? std::span<const DebugInfoFunctionRecord>{records.functions} : std::span<const DebugInfoFunctionRecord>{debugFunctions},
                .emitCodeView    = false,
                .emitDwarf       = emitDwarf,
            };

            return DebugInfo::buildObject(debugInfoRequest, debugInfoResult);
        }

        Result placeUnwindSections(DebugInfoObjectResult& debugInfoResult)
        {
            std::unordered_map<Utf8, SectionPlacement> placements;
            for (NativeSectionData& section : debugInfoResult.sections)
            {
                if (section.name.view().starts_with(".debug") && builder_->ctx().cmdLine().targetOs != Runtime::TargetOs::Linux)
                    continue;
                SectionPlacement placement;
                SWC_RESULT(appendNativeSection(placement, std::move(section)));
                placements.emplace(section.name, placement);
            }
            for (const DebugInfoDefinedSymbol& symbol : debugInfoResult.symbols)
            {
                const auto placement = placements.find(symbol.sectionName);
                SWC_ASSERT(placement != placements.end() && placement->second.valid);
                if (placement == placements.end() || !placement->second.valid)
                    return builder_->reportError(DiagnosticId::cmd_err_link_reloc_out_of_bounds);
                addSymbol(symbol.name, placement->second.index, placement->second.base + symbol.value);
            }

            return Result::Continue;
        }

        Result appendNativeSection(SectionPlacement& outPlacement, const NativeSectionData& section)
        {
            if (!placeNativeSection(outPlacement, section))
                return Result::Continue;

            for (const NativeSectionRelocation& relocation : section.relocations)
                SWC_RESULT(appendRelocation(outPlacement.index, outPlacement.base, section.name, relocation, Utf8{relocation.symbolName}));

            return Result::Continue;
        }

        // Transfer relocation names from a consumed section to avoid copying
        // and allocating a symbol name for every relocation.
        Result appendNativeSection(SectionPlacement& outPlacement, NativeSectionData&& section)
        {
            if (!placeNativeSection(outPlacement, section))
                return Result::Continue;

            for (NativeSectionRelocation& relocation : section.relocations)
                SWC_RESULT(appendRelocation(outPlacement.index, outPlacement.base, section.name, relocation, std::move(relocation.symbolName)));

            return Result::Continue;
        }

        // False when the section takes no place in the image.
        bool placeNativeSection(SectionPlacement& outPlacement, const NativeSectionData& section)
        {
            outPlacement       = {};
            const bool isDebug = section.name.view().starts_with(".debug");
            if (isDebug && builder_->ctx().cmdLine().targetOs != Runtime::TargetOs::Linux)
                return false;

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
            const uint32_t align = applyNativeSectionCoffProperties(linkSection, section);
            if (isDebug)
                linkSection.flags.add(LinkSectionFlagsE::Debug);

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

            return true;
        }

        Result appendRelocation(const uint32_t sectionIndex, const uint32_t base, const Utf8& sectionName, const NativeSectionRelocation& relocation, Utf8&& symbolName) const
        {
            LinkRelocKind kind;
            uint32_t      width;
            switch (relocation.kind)
            {
                case NativeRelocationKind::Abs64:
                    kind  = LinkRelocKind::Abs64;
                    width = 8;
                    break;
                case NativeRelocationKind::Rva32:
                    kind  = LinkRelocKind::Rva32;
                    width = 4;
                    break;
                case NativeRelocationKind::Rel32:
                    kind  = LinkRelocKind::Rel32;
                    width = 4;
                    break;
                case NativeRelocationKind::GotRel32:
                    kind  = LinkRelocKind::GotRel32;
                    width = 4;
                    break;
                default:
                    return builder_->reportError(DiagnosticId::cmd_err_link_coff_unsupported_reloc, Diagnostic::ARG_VALUE, std::to_string(static_cast<uint32_t>(relocation.kind)), Diagnostic::ARG_TARGET, sectionName);
            }

            LinkSection&   section     = image_->sections[sectionIndex];
            const uint32_t patchOffset = base + relocation.offset;
            if (!section.bytes.containsRange(patchOffset, width))
                return builder_->reportError(DiagnosticId::cmd_err_link_reloc_out_of_bounds);
            if (width == 8)
                section.bytes.writeLe64(patchOffset, relocation.addend);
            else
                section.bytes.writeLe32(patchOffset, static_cast<uint32_t>(relocation.addend));

            LinkReloc linkReloc;
#if SWC_DEBUG_MODE
            linkReloc.sectionIndex = sectionIndex;
#endif
            linkReloc.offset     = patchOffset;
            linkReloc.symbolName = std::move(symbolName);
            linkReloc.kind       = kind;
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

        NativeBackendBuilder* builder_ = nullptr;
        LinkImage*            image_   = nullptr;

        std::unordered_map<Utf8, uint32_t> sectionByName_;
        std::unordered_set<Utf8>           definedNames_;
    };

}

Result NativeImageBuilder::build(LinkImage& image, NativeBackendBuilder& builder)
{
    NativeImageLowering lowering(builder, image);

    // Each description's code, relocations and unwind records are independent of every other
    // one; only their placement in the image is ordered.
    const auto&                                 descriptions = builder.objectDescriptions;
    std::vector<NativeImageDescriptionSections> sections(descriptions.size());
    std::vector<Result>                         results(descriptions.size(), Result::Continue);

    JobManager& jobMgr = builder.ctx().global().jobMgr();
    jobMgr.parallelForIndexed(builder.ctx(), static_cast<uint32_t>(descriptions.size()), JobKind::NativeLinkPrepare, jobMgr.newClientId(), [&](TaskContext&, const uint32_t index) {
        results[index] = lowering.buildDescription(sections[index], descriptions[index]);
    });

    for (size_t index = 0; index < descriptions.size(); ++index)
    {
        SWC_RESULT(results[index]);
        SWC_RESULT(lowering.placeDescription(sections[index], descriptions[index]));
    }

    return Result::Continue;
}

Result NativeImageBuilder::buildObject(LinkImage& image, NativeBackendBuilder& builder, const NativeObjDescription& description)
{
    NativeImageLowering lowering(builder, image);
    NativeImageDescriptionSections sections;
    SWC_RESULT(lowering.buildDescription(sections, description));
    return lowering.placeDescription(sections, description);
}

SWC_END_NAMESPACE();
