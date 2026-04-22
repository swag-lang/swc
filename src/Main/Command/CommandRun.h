#pragma once

#include "Compiler/Sema/Core/Sema.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE();

namespace CommandRun
{
    template<typename FUNC>
    Result afterPauses(TaskContext& ctx, const FUNC& func)
    {
        while (true)
        {
            const Result result = func();
            if (result != Result::Pause)
                return result;

            Sema::waitDone(ctx, ctx.compiler().jobClientId());
            if (Stats::hasError())
                return Result::Error;
        }
    }
}

SWC_END_NAMESPACE();
