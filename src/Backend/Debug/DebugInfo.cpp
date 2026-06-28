#include "pch.h"
#include "Support/Report/Assert.h"
#include "Backend/Debug/DebugInfo.h"
#include "Backend/Debug/DebugInfoCodeView.h"
#include "Compiler/SourceFile.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"
#include "Support/Math/Sha256.h"

SWC_BEGIN_NAMESPACE();

std::array<uint8_t, 32> DebugInfo::sourceFileChecksum(const TaskContext& ctx, const SourceFile& file)
{
    // For generated sources the on-disk .swgsrc is the concatenation of every section produced on a thread,
    // while file.sourceView() is just one section. Hash the full in-memory dump (final by link time, so no
    // race with the on-disk flush) so the checksum matches what a debugger re-hashes from disk.
    std::string_view content;
    if (file.hasFlag(FileFlagsE::CustomSrc) && ctx.compiler().tryGetGeneratedSourceContent(file.path(), content))
        return sha256(asByteSpan(content));
    return sha256(asByteSpan(file.sourceView()));
}

std::unique_ptr<DebugInfo> DebugInfo::create(const Runtime::TargetOs targetOs)
{
    switch (targetOs)
    {
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
