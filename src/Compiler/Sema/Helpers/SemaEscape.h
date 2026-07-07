#pragma once
#include "Compiler/Lexer/SourceCodeRange.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"
#include "Support/Core/StrongRef.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class SourceFile;
class SymbolFunction;
class SymbolVariable;
class TaskContext;
enum class DiagnosticId;
using FileRef = StrongRef<SourceFile>;

// A call whose result may borrow one of its arguments, recorded while analyzing the
// caller and judged once the whole module is sema-completed: only then is the callee's
// 'returnBorrowsParamsMask' final, whatever order the sema jobs ran in.
struct SemaEscapeDeferredCheck
{
    const SymbolFunction* callee     = nullptr;
    uint32_t              paramIndex = 0;
    DiagnosticId          diagId     = {};
    FileRef               fileRef;
    SourceCodeRange       siteRange;
    Utf8                  symName;
    Utf8                  what;
    TypeRef               typeRef;
    DiagnosticId          noteId = {};
    Utf8                  noteSymName;
    SourceCodeRange       noteRange;
};

// A return-position call that hands one of the caller's own parameters to the callee:
// if the callee's return value borrows that parameter, so does the caller's. Resolved
// by a mask fixpoint in reportDeferredChecks, making the per-function summaries
// transitive across chains of opaque calls (a wrapper level no longer hides a borrow).
struct SemaEscapeSummaryEdge
{
    SymbolFunction*       caller           = nullptr;
    const SymbolFunction* callee           = nullptr;
    uint32_t              callerParamIndex = 0;
    uint32_t              calleeParamIndex = 0;
};

namespace SemaEscape
{
    bool   typeCanCarryBorrow(Sema& sema, TypeRef typeRef);
    Result checkVariableInitializer(Sema& sema, const SymbolVariable& symVar, AstNodeRef initRef, TypeRef targetTypeRef);
    Result applyAssignment(Sema& sema, AstNodeRef leftRef, AstNodeRef rightRef);
    Result checkReturn(Sema& sema, AstNodeRef returnRef, AstNodeRef exprRef, TypeRef returnTypeRef, const SymbolFunction* inlineSourceFn);
    void   bindForeachAddressAlias(Sema& sema, const SymbolVariable& symVar, AstNodeRef exprRef);

    // Judges the deferred call-site records against the (now final) per-function borrow
    // summaries. Runs once the module has no pending sema job (Sema::waitDone).
    void reportDeferredChecks(TaskContext& ctx);
}

SWC_END_NAMESPACE();
