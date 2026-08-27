#pragma once
#include "Compiler/Lexer/SourceCodeRange.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"
#include "Support/Core/SmallVector.h"
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
struct SemaEscapeDeferredGuard
{
    const SymbolFunction* callee     = nullptr;
    uint32_t              paramIndex = 0;
    // Judged against the callee's RETURNS-PAYLOAD summary instead of its RETURN one: the
    // result must be a view INTO what the parameter owns, not merely a value that can
    // reach it. Only the invalidation check needs the stronger question.
    bool requirePayload = false;

    bool operator==(const SemaEscapeDeferredGuard&) const noexcept = default;
};

struct SemaEscapeDeferredCheck
{
    const SymbolFunction* callee     = nullptr;
    uint32_t              paramIndex = 0;
    // Judged against the callee's STORES summary (the callee keeps its argument beyond
    // the call) instead of its RETURN summary (the call result carries the borrow).
    bool judgeStores = false;
    // Every preceding call in a chained local must return the borrow for it to reach
    // the final judged call. A list avoids an arbitrary composition-depth limit.
    SmallVector4<SemaEscapeDeferredGuard> guards;
    // Judged against the callee's PAIR summary instead: parameter #paramIndex stored
    // into storage reachable from parameter #intoParamIndex, whose argument at this
    // site provably outlives the borrowed one.
    bool     judgePairs     = false;
    uint32_t intoParamIndex = 0;
    // No summary condition at all: the fault is certain from the callee's identity
    // (a frame borrow handed to 'IAllocator.free' as the request address).
    bool judgeAlways = false;
    // The borrowed argument roots at a GLOBAL. Nothing can escape through it - a global
    // outlives every frame - so this record is never judged as an escape. It exists only
    // to carry the route back to the owner, which is what tells the invalidation check
    // that a call result reads what that global owns.
    bool staticSource = false;
    // The borrowed source is an owner (its payload lives on the heap): freeing it is
    // legitimate, so a FREES-only match must stay silent.
    bool ownerSource = false;
    // The local the borrowed argument roots at. 'symName' is what the diagnostic prints;
    // this is the identity, for the checks that must match a route back to a variable.
    const SymbolVariable* borrowedVar = nullptr;
    DiagnosticId          diagId      = {};
    FileRef               fileRef;
    SourceCodeRange       siteRange;
    Utf8                  symName;
    Utf8                  what;
    TypeRef               typeRef;
    DiagnosticId          noteId = {};
    Utf8                  noteSymName;
    SourceCodeRange       noteRange;
    // A second note, for the checks that need to show two places at once (where a view
    // was taken, and where it is read again after its storage moved).
    DiagnosticId    note2Id = {};
    Utf8            note2SymName;
    SourceCodeRange note2Range;
    // Judged against the callee's REALLOCATES summary: the call can move or release the
    // payload its receiver owns, so a view into that payload read afterwards is stale.
    bool judgeReallocates = false;
    // First receiver field of the saved view and of the mutation site. Null means the
    // receiver itself. The callee summary supplies its own first field at final judgement.
    const SymbolVariable* borrowedPayloadField    = nullptr;
    const SymbolVariable* receiverProjectionField = nullptr;
    Utf8                  valueName;
};

// A structural change of storage that a local view was reading. Recorded where the flow
// state proves the view is live, and judged once the whole body is resolved - only then
// can later reads, including reads reached through a loop back edge, be matched to symbols.
struct SemaBorrowInvalidation
{
    const SymbolVariable* viewVar   = nullptr;
    const SymbolVariable* sourceVar = nullptr;
    const SymbolFunction* callee    = nullptr;
    // The complete function or inline-expansion body that owns this mutation. Capturing
    // it here avoids consulting the caller's partially substituted tree at report time.
    AstNodeRef bodyRef = AstNodeRef::invalid();
    // The node, not only its range, lets a back-edge check distinguish a break of
    // this loop from a break owned by a nested loop or switch.
    AstNodeRef      mutationRef = AstNodeRef::invalid();
    SourceCodeRange mutationRange;
    // Where the call's own text ends. Arguments are evaluated BEFORE the callee runs, so
    // a view named inside them is read before the change, not after it: the search for a
    // later read starts past the whole call expression, not past its name.
    uint32_t              evaluationEndOffset = 0;
    Utf8                  mutationName;
    const SymbolVariable* borrowedPayloadField    = nullptr;
    const SymbolVariable* receiverProjectionField = nullptr;
    // What the view's provenance depends on. A view taken straight out of the storage
    // needs nothing; one obtained from an accessor call only aliases the receiver when
    // that accessor's return summary says so, and summaries are final only once the
    // module is drained.
    SmallVector4<SemaEscapeDeferredGuard> guards;
};

// How a callee's summary propagates into the caller's when a call receives one of the
// caller's own parameters as an argument.
enum class SemaEscapeSummaryEdgeKind : uint8_t
{
    ReturnToReturn, // return-position call: callee returns #j -> caller returns #i
    ReturnToStores, // result stored durably: callee returns #j -> caller stores #i
    StoresToStores, // any call: callee stores #j -> caller stores #i
    PairToPair,     // callee stores #j into #k -> caller stores mapped #i into #h
    ReturnToPair,   // callee RETURNS storage of #j, and the caller stored #i through that
                    // result: caller stores #i into its own parameter #h
};

// A call that hands one of the caller's own parameters to the callee: whatever the
// callee's summary says about that parameter flows into the caller's summary. Resolved
// by a mask fixpoint in reportDeferredChecks, making the per-function summaries
// transitive across chains of opaque calls (a wrapper level no longer hides a borrow).
struct SemaEscapeSummaryEdge
{
    SymbolFunction*           caller               = nullptr;
    const SymbolFunction*     callee               = nullptr;
    uint32_t                  callerParamIndex     = 0;
    uint32_t                  calleeParamIndex     = 0;
    uint32_t                  callerIntoParamIndex = 0;
    uint32_t                  calleeIntoParamIndex = 0;
    SemaEscapeSummaryEdgeKind kind                 = SemaEscapeSummaryEdgeKind::ReturnToReturn;
    // The argument was a payload the parameter OWNS, not the parameter's own storage.
    // The borrow still propagates, but the FREES summary must not: releasing what an
    // object owns does not release the object.
    bool viaOwnedPayload = false;
    // The argument only CARRIES the parameter in one of its fields; its own storage is a
    // distinct allocation. The borrow still propagates, and so does the STORES summary,
    // but the FREES summary must not: releasing the carrier releases the carrier.
    bool viaStoredField = false;
    // First field used to reach the callee argument from the caller parameter. A callee
    // reallocation then affects this field, whatever nested payload it moves internally.
    const SymbolVariable* callerProjectionField = nullptr;
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

    // '@setcontext' stores a POINTER to its argument in runtime-owned storage that
    // outlives the frame, so installing a frame local and returning leaves every later
    // '@getcontext' reading recycled stack. Silent when the body restores a previous
    // context with a 'defer', which is what makes the scoped idiom sound.
    Result checkSetContext(Sema& sema, AstNodeRef intrinsicRef, AstNodeRef argRef);

    // Judges the deferred call-site records against the (now final) per-function borrow
    // summaries. Runs once the module has no pending sema job (Sema::waitDone).
    void reportDeferredChecks(TaskContext& ctx);
}

SWC_END_NAMESPACE();
