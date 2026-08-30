#pragma once
#include "Compiler/Sema/Helpers/SemaEscapeTypes.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class TaskContext;

namespace SemaEscape
{
    bool   typeCanCarryBorrow(Sema& sema, TypeRef typeRef);
    Result checkVariableInitializer(Sema& sema, const SymbolVariable& symVar, AstNodeRef initRef, TypeRef targetTypeRef);
    Result applyAssignment(Sema& sema, AstNodeRef leftRef, AstNodeRef rightRef);
    Result checkReturn(Sema& sema, AstNodeRef returnRef, AstNodeRef exprRef, TypeRef returnTypeRef, const SymbolFunction* inlineSourceFn);
    void   bindForeachAddressAlias(Sema& sema, const SymbolVariable& symVar, AstNodeRef exprRef);

    // The storage variable a 'foreach' source expression ultimately reads (through an
    // opCast-to-slice, a reference binding, aliases, ...). Registered as the loop's
    // iteration borrow so a structural mutation of that same variable inside the body is
    // flagged. Null when the source has no single storage root (a range, a temporary).
    const SymbolVariable* iterationSourceRoot(Sema& sema, AstNodeRef exprRef);

    // Reports when a resolved call structurally mutates a collection that an enclosing
    // loop is iterating (the receiver roots at an active iteration borrow, and the callee
    // is a non-const, non-operator method: add/remove/clear/free ...).
    Result checkIterationMutation(Sema& sema, AstNodeRef callRef, const SymbolFunction& calledFn);

    // Records a resolved call that structurally changes storage a local view is reading
    // ('let v: string = s; s.append("..."); use(v)'). The iteration check above is this
    // same rule restricted to loops.
    void noteBorrowInvalidation(Sema& sema, AstNodeRef callRef, const SymbolFunction& calledFn);

    // Judges the recorded changes against the fully resolved body: a read of the view
    // written after the change reads storage the change may have moved or freed.
    Result reportBorrowInvalidations(Sema& sema, AstNodeRef declRef);

    // Called on every resolved opaque call: records the "callee stores its argument"
    // deferred checks for borrowed arguments, and the stores-propagation edges for
    // caller-parameter arguments.
    void noteCallArguments(Sema& sema, AstNodeRef callRef);

    // 'Swag.setContext' stores a POINTER to its argument in runtime-owned storage that
    // outlives the frame, so installing a frame local and returning leaves every later
    // 'Swag.getContext' reading recycled stack. Silent when the body restores a previous
    // context with a 'defer', which is what makes the scoped idiom sound.
    Result checkSetContext(Sema& sema, AstNodeRef intrinsicRef, AstNodeRef argRef);

    // Judges the deferred call-site records against the (now final) per-function borrow
    // summaries. Runs once the module has no pending sema job (Sema::waitDone).
    void reportDeferredChecks(TaskContext& ctx);
}

SWC_END_NAMESPACE();
