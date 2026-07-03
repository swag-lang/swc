#include "pch.h"
#include "Backend/Micro/Passes/Pass.Sanity.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Sanitizer/DivByZeroCheck.h"
#include "Backend/Sanitizer/NullDerefCheck.h"
#include "Backend/Sanitizer/Sanitizer.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

Result MicroSanityPass::run(MicroPassContext& context)
{
    context.passChanged = false;

    if (context.sanitizerSafetyMask == 0)
        return Result::Continue;
    if (!context.instructions || !context.operands || !context.taskContext || !context.builder)
        return Result::Continue;

    // Register every available check, then keep only those whose safety guard is enabled
    // for this function. Adding a check is: subclass SanitizerCheck and list it here.
    NullDerefCheck nullDerefCheck;
    DivByZeroCheck divByZeroCheck;
    SanitizerCheck* const allChecks[] = {&nullDerefCheck, &divByZeroCheck};

    SmallVector<SanitizerCheck*> enabledChecks;
    for (SanitizerCheck* check : allChecks)
        if (context.sanitizerSafetyMask & static_cast<uint16_t>(check->safety()))
            enabledChecks.push_back(check);

    if (enabledChecks.empty())
        return Result::Continue;

    // On a proven finding, abort codegen so the faulty function is never emitted or run.
    // The reported error fails the build (or is matched by a test's expected-error
    // marker); a function that legitimately produced no code because it errored is
    // skipped by the backend's missing-code validation.
    Sanitizer sanitizer(context);
    if (sanitizer.run(enabledChecks.span()))
        return Result::Error;
    return Result::Continue;
}

SWC_END_NAMESPACE();
