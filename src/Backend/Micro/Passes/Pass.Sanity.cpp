#include "pch.h"
#include "Backend/Micro/Passes/Pass.Sanity.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Sanitizer/NullDerefAnalysis.h"

SWC_BEGIN_NAMESPACE();

Result MicroSanityPass::run(MicroPassContext& context)
{
    context.passChanged = false;

    // The sanitizer runs only when the function's effective `SafetyWhat::Null` guard is
    // on (set by the caller: build-config default combined with `#[Swag.Safety(.Null)]`
    // overrides). It is therefore a no-op in release/fast-compile by default.
    if (!context.nullSanitizerEnabled)
        return Result::Continue;
    if (!context.instructions || !context.operands || !context.taskContext || !context.builder)
        return Result::Continue;

    // On a proven null dereference, abort codegen so the faulty function is never emitted
    // or run. The reported error fails the build (or is matched by a test's expected-error
    // marker); a function that legitimately produced no code because it errored is skipped
    // by the backend's missing-code validation.
    NullDerefAnalysis analysis(context);
    if (analysis.run())
        return Result::Error;
    return Result::Continue;
}

SWC_END_NAMESPACE();
