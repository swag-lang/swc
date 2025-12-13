#pragma once

SWC_BEGIN_NAMESPACE()

enum class AstVisitResult
{
    Continue, // normal flow
    Pause,    // abort traversal immediately, but we are not finished
    Stop      // abort traversal immediately
};

enum class AstVisitStepResult
{
    Continue,     // normal flow
    SkipChildren, // don't descend, go straight to post()
    Pause,        // abort traversal immediately, but we are not finished
    Stop          // abort traversal immediately
};

SWC_END_NAMESPACE()
