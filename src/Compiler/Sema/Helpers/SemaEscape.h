#pragma once
#include "Compiler/Sema/Helpers/SemaEscapeTypes.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class TaskContext;

namespace SemaEscape
{
    bool typeCanCarryBorrow(Sema& sema, TypeRef typeRef);

    Result checkVariableInitializer(Sema& sema, const SymbolVariable& symVar, AstNodeRef initRef, TypeRef targetTypeRef);
    Result applyAssignment(Sema& sema, AstNodeRef leftRef, AstNodeRef rightRef);
    Result checkReturn(Sema& sema, AstNodeRef returnRef, AstNodeRef exprRef, TypeRef returnTypeRef, const SymbolFunction* inlineSourceFn);

    void finalizeBorrowStores(Sema& sema, SymbolFunction& function, AstNodeRef bodyRef);

    void bindForeachAddressAlias(Sema& sema, const SymbolVariable& symVar, AstNodeRef exprRef);

    // Track the foreach source's storage through casts, aliases, and references
    // to detect mutation during iteration. Ranges and temporaries have no single root.
    const SymbolVariable* iterationSourceRoot(Sema& sema, AstNodeRef exprRef);

    // Reject structural mutation of a collection borrowed by an enclosing loop.
    Result checkIterationMutation(Sema& sema, AstNodeRef callRef, const SymbolFunction& calledFn);

    // Record structural storage changes while local views are live; iteration
    // mutation checks apply the same rule specifically to loops.
    void noteBorrowInvalidation(Sema& sema, AstNodeRef callRef, const SymbolFunction& calledFn);

    // Check later view reads after the entire body has resolved.
    Result reportBorrowInvalidations(Sema& sema, AstNodeRef declRef);

    // Opaque calls defer retained-argument checks and record summary propagation
    // when arguments borrow the caller's parameters.
    void noteCallArguments(Sema& sema, AstNodeRef callRef);

    // setContext retains a pointer beyond this frame, so local storage would
    // dangle after return. A defer restoring the old context makes scoped use safe.
    Result checkSetContext(Sema& sema, AstNodeRef intrinsicRef, AstNodeRef argRef);

    // Judge deferred records against final summaries after Sema::waitDone drains jobs.
    void reportDeferredChecks(TaskContext& ctx);

    // Compile-time execution can lower a completed call graph before the module-wide
    // summary pass. Publish the transitive release facts available for that graph first.
    void propagateCompletedFreesSummaries(TaskContext& ctx, std::span<SymbolFunction* const> completedFunctions, uint64_t orderFingerprint = 0);
}

SWC_END_NAMESPACE();
