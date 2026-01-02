#pragma once

SWC_BEGIN_NAMESPACE()

enum class AstStepResult
{
    Continue,     // normal flow
    SkipChildren, // don't descend, go straight to post()
    Pause,        // abort traversal immediately, but we are not finished
    Stop          // abort traversal immediately
};

#define AST_VERIFY(__expr)                              \
    if (const ret = __expr; ret != AstResult::Continue) \
        return ret;

SWC_END_NAMESPACE()
