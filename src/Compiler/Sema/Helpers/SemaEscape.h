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
    // Judged against the callee's STORES summary (the callee keeps its argument beyond
    // the call) instead of its RETURN summary (the call result carries the borrow).
    bool judgeStores = false;
    // Optional second condition: 'let p = f(&v); g(p)' escapes only if 'f' RETURNS the
    // borrow of 'v' (the guard) AND 'g' keeps/returns its argument (the main judge).
    const SymbolFunction* guardCallee     = nullptr;
    uint32_t              guardParamIndex = 0;
    // Judged against the callee's PAIR summary instead: parameter #paramIndex stored
    // into storage reachable from parameter #intoParamIndex, whose argument at this
    // site is a global.
    bool     judgePairs     = false;
    uint32_t intoParamIndex = 0;
    DiagnosticId    diagId      = {};
    FileRef         fileRef;
    SourceCodeRange siteRange;
    Utf8            symName;
    Utf8            what;
    TypeRef         typeRef;
    DiagnosticId    noteId = {};
    Utf8            noteSymName;
    SourceCodeRange noteRange;
};

// How a callee's summary propagates into the caller's when a call receives one of the
// caller's own parameters as an argument.
enum class SemaEscapeSummaryEdgeKind : uint8_t
{
    ReturnToReturn, // return-position call: callee returns #j -> caller returns #i
    ReturnToStores, // result stored durably: callee returns #j -> caller stores #i
    StoresToStores, // any call: callee stores #j -> caller stores #i
};

// A call that hands one of the caller's own parameters to the callee: whatever the
// callee's summary says about that parameter flows into the caller's summary. Resolved
// by a mask fixpoint in reportDeferredChecks, making the per-function summaries
// transitive across chains of opaque calls (a wrapper level no longer hides a borrow).
struct SemaEscapeSummaryEdge
{
    SymbolFunction*           caller           = nullptr;
    const SymbolFunction*     callee           = nullptr;
    uint32_t                  callerParamIndex = 0;
    uint32_t                  calleeParamIndex = 0;
    SemaEscapeSummaryEdgeKind kind             = SemaEscapeSummaryEdgeKind::ReturnToReturn;
};

// The captured argument borrows of one opaque call. Checks are templates whose site,
// wording and judged summary are stamped when the borrow provably escapes; edges are
// proto-edges whose kind is chosen by the escape flavor. Also stored per-Sema when the
// call result is bound to a local ('let p = f(&v)'), so the judgement happens only if
// that local later escapes ('return p').
struct SemaEscapeDeferredCallSnapshot
{
    std::vector<SemaEscapeDeferredCheck> checks;
    std::vector<SemaEscapeSummaryEdge>   edges;
};

namespace SemaEscape
{
    bool   typeCanCarryBorrow(Sema& sema, TypeRef typeRef);
    Result checkVariableInitializer(Sema& sema, const SymbolVariable& symVar, AstNodeRef initRef, TypeRef targetTypeRef);
    Result applyAssignment(Sema& sema, AstNodeRef leftRef, AstNodeRef rightRef);
    Result checkReturn(Sema& sema, AstNodeRef returnRef, AstNodeRef exprRef, TypeRef returnTypeRef, const SymbolFunction* inlineSourceFn);
    void   bindForeachAddressAlias(Sema& sema, const SymbolVariable& symVar, AstNodeRef exprRef);

    // Called on every resolved opaque call: records the "callee stores its argument"
    // deferred checks for borrowed arguments, and the stores-propagation edges for
    // caller-parameter arguments.
    void noteCallArguments(Sema& sema, AstNodeRef callRef);

    // Judges the deferred call-site records against the (now final) per-function borrow
    // summaries. Runs once the module has no pending sema job (Sema::waitDone).
    void reportDeferredChecks(TaskContext& ctx);
}

SWC_END_NAMESPACE();
