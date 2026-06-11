#include "pch.h"
#include "Support/Thread/Job.h"

SWC_BEGIN_NAMESPACE();

const char* Job::kindName(const JobKind kind)
{
    switch (kind)
    {
        case JobKind::Invalid:
            return "Invalid";
        case JobKind::Format:
            return "Format";
        case JobKind::Parser:
            return "Parser";
        case JobKind::Sema:
            return "Sema";
        case JobKind::CodeGen:
            return "CodeGen";
        case JobKind::JitPatch:
            return "JitPatch";
        case JobKind::CompilerMessage:
            return "CompilerMessage";
        case JobKind::NativeArtifact:
            return "NativeArtifact";
        case JobKind::NativeObj:
            return "NativeObj";
        case JobKind::NativeLink:
            return "NativeLink";
        case JobKind::ModuleApiExport:
            return "ModuleApiExport";
        default:
            return "Unknown";
    }
}

JobResult Job::toJobResult(const TaskContext& ctx, Result result)
{
    if (result == Result::Pause)
    {
        // Sleeping jobs must expose an actionable wait state so deadlock/error reporting
        // can attribute the pause to the right semantic dependency.
        SWC_INTERNAL_CHECK(ctx.state().canPause());
        return JobResult::Sleep;
    }

    return JobResult::Done;
}

SWC_END_NAMESPACE();
