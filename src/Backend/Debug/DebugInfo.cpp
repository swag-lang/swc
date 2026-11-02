#include "pch.h"
#include "Backend/Debug/DebugInfo.h"
#include "Backend/Debug/DebugInfoCodeView.h"
#include "Backend/Encoder/X64DwarfFrame.h"
#include "Backend/Linker/PEFormat.h"
#include "Backend/Micro/MachineCode.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    class DebugInfoDwarf final : public DebugInfo
    {
    public:
        Result buildObject(DebugInfoObjectResult& outResult, const DebugInfoObjectRequest& request) override
        {
            outResult = {};
            NativeSectionData section;
            section.name = ".eh_frame";
            section.characteristics = PE::SCN_CNT_INITIALIZED_DATA | PE::SCN_MEM_READ | PE::SCN_ALIGN_8BYTES;
            for (const DebugInfoFunctionRecord& function : request.functions)
            {
                if (!function.machineCode || function.machineCode->bytes.empty())
                    continue;
                uint32_t addressOffset = 0;
                if (!X64DwarfFrame::appendObjectFrame(section.bytes, addressOffset, function.machineCode->unwindInfo, static_cast<uint32_t>(function.machineCode->bytes.size())))
                {
                    Diagnostic diagnostic = Diagnostic::get(DiagnosticId::cmd_err_link_elf_object);
                    diagnostic.addArgument(Diagnostic::ARG_BECAUSE, std::format("function '{}' has no matching DWARF frame", function.symbolName));
                    diagnostic.report(*request.ctx);
                    return Result::Error;
                }
                section.relocations.push_back({.offset = addressOffset, .symbolName = function.symbolName, .addend = 4, .kind = NativeRelocationKind::Rel32});
            }
            if (!section.bytes.empty())
            {
                section.bytes.appendLe32(0);
                outResult.sections.push_back(std::move(section));
            }
            return Result::Continue;
        }

        void buildPdbInfo(DebugInfoPdbResult& outResult, const DebugInfoObjectRequest&) override
        {
            // ELF does not publish a PDB. Source-level DWARF records have a separate format.
            outResult = {};
        }
    };
}

std::unique_ptr<DebugInfo> DebugInfo::create(const Runtime::TargetOs targetOs)
{
    switch (targetOs)
    {
        case Runtime::TargetOs::Linux:
            return std::make_unique<DebugInfoDwarf>();
        case Runtime::TargetOs::Windows:
            return std::make_unique<DebugInfoCodeView>();
    }

    SWC_UNREACHABLE();
}

Result DebugInfo::buildObject(const DebugInfoObjectRequest& request, DebugInfoObjectResult& outResult)
{
    const auto debugInfo = create(request.targetOs);
    return debugInfo->buildObject(outResult, request);
}

void DebugInfo::buildPdbInfo(const DebugInfoObjectRequest& request, DebugInfoPdbResult& outResult)
{
    const auto debugInfo = create(request.targetOs);
    debugInfo->buildPdbInfo(outResult, request);
}

SWC_END_NAMESPACE();
