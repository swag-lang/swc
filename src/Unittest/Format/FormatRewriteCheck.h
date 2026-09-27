#pragma once
#include "Format/FormatOptions.h"
#include "Format/Formatter.h"
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE();

namespace FormatRewriteCheck
{
    inline Result check(const TaskContext& parentCtx, std::string_view source, std::string_view expected, const FormatOptions& options)
    {
        Formatter formatter(options);
        SWC_RESULT(formatter.prepare(parentCtx.global(), source));
        if (formatter.text() != expected)
            return Result::Error;

        Formatter secondPass(options);
        SWC_RESULT(secondPass.prepare(parentCtx.global(), formatter.text()));
        if (secondPass.text() != expected)
            return Result::Error;
        return Result::Continue;
    }
}

SWC_END_NAMESPACE();
