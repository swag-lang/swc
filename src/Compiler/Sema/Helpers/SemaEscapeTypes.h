#pragma once
#include "Compiler/Lexer/SourceCodeRange.h"
#include "Compiler/SourceFile.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/SmallVector.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;
class SymbolVariable;
enum class DiagnosticId;

// Defer call-result borrow checks until module completion, when the callee's
// returnBorrowsParamsMask is final regardless of job order.
struct SemaEscapeDeferredGuard
{
    const SymbolFunction* callee     = nullptr;
    uint32_t              paramIndex = 0;

    // Each call must preserve storage or expose a payload, with at least one
    // payload accessor. Lifetime dependencies alone do not prove allocation aliasing.
    bool requireStorageRoute = false;
    bool indirect            = false; // consult returnsIndirect instead of returns

    bool operator==(const SemaEscapeDeferredGuard&) const noexcept = default;
};

struct SemaEscapeDeferredCheck
{
    const SymbolFunction* callee     = nullptr;
    uint32_t              paramIndex = 0;
    bool                  indirect   = false; // judge the copied pointee contents

    // Check retained arguments (STORES), rather than borrows in the result (RETURN).
    bool judgeStores = false;

    // Every preceding call in a chained local must return the borrow for it to reach
    // the final judged call. A list avoids an arbitrary composition-depth limit.
    SmallVector4<SemaEscapeDeferredGuard> guards;

    // PAIR checks track paramIndex stored through intoParamIndex, whose argument
    // is proven to outlive the borrowed one at this site.
    bool     judgePairs     = false;
    uint32_t intoParamIndex = 0;

    // Certain from callee identity, such as a frame address sent to IAllocator.free.
    bool judgeAlways = false;

    // Global storage outlives every frame, so this is not an escape error.
    // Keep provenance back to the owning global for invalidation checks.
    bool staticSource = false;

    // Provenance-only snapshot (not an escape diagnostic), used when an accessor result
    // inside a method routes back to the caller-owned receiver parameter.
    bool routeOnly = false;

    // Releasing an owner's heap payload is valid; a FREES-only match stays silent.
    bool ownerSource = false;

    // Releasing a separate carrier does not release the data referenced by its fields.
    bool viaStoredField = false;

    // Variable identity for provenance matching; symName supplies diagnostic text.
    const SymbolVariable* borrowedVar = nullptr;
    DiagnosticId          diagId      = {};
    FileRef               fileRef;
    SourceCodeRange       siteRange;
    Utf8                  symName;
    Utf8                  what;
    TypeRef               typeRef;

    DiagnosticId    noteId = {};
    Utf8            noteSymName;
    SourceCodeRange noteRange;

    // Some checks highlight both view creation and a later read after mutation.
    DiagnosticId    note2Id = {};
    Utf8            note2SymName;
    SourceCodeRange note2Range;

    // REALLOCATES checks detect later reads of payloads the callee may move or free.
    bool judgeReallocates = false;

    // First receiver field of the saved view and of the mutation site. Null means the
    // receiver itself. The callee summary supplies its own first field at final judgement.
    const SymbolVariable*               borrowedPayloadField    = nullptr;
    const SymbolVariable*               receiverProjectionField = nullptr;
    SmallVector4<const SymbolVariable*> detachedPayloadFields;
    Utf8                                valueName;
};

// Record mutations while flow facts prove a view live. Check later reads after
// body resolution, when symbols and loop back-edge uses can be matched reliably.
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

    // Arguments are read before the callee mutates storage. Search for later
    // uses after the whole call expression, not after its name.
    uint32_t evaluationEndOffset = 0;
    Utf8     mutationName;

    const SymbolVariable*               borrowedPayloadField    = nullptr;
    const SymbolVariable*               receiverProjectionField = nullptr;
    SmallVector4<const SymbolVariable*> detachedPayloadFields;

    // Accessor results alias a receiver only when its final return summary says
    // so. Direct storage views need no guard; accessor routes wait for module drain.
    SmallVector4<SemaEscapeDeferredGuard> guards;
};

// How a callee's summary propagates into the caller's when a call receives one of the
// caller's own parameters as an argument.
enum class SemaEscapeSummaryEdgeKind : uint8_t
{
    ExternalToExternal, // callee can observe ambient borrows -> caller can too
    RetentionToPair,    // a call can retain/return an alias of the receiver before a store
    ExternalToPair,     // an observer in a live-slot interval prevents eliding that store

    ReturnToReturn, // return-position call: callee returns #j -> caller returns #i
    ReturnToStores, // result stored durably: callee returns #j -> caller stores #i
    StoresToStores, // any call: callee stores #j -> caller stores #i

    PairToPair,   // callee stores #j into #k -> caller stores mapped #i into #h
    ReturnToPair, // callee RETURNS storage of #j, and the caller stored #i through that
                  // result: caller stores #i into its own parameter #h
};

// Propagate callee effects on a caller parameter through opaque call chains.
// reportDeferredChecks resolves these edges with a mask fixpoint.
struct SemaEscapeSummaryEdge
{
    SymbolFunction*       caller = nullptr;
    const SymbolFunction* callee = nullptr;

    uint32_t callerParamIndex     = 0;
    uint32_t calleeParamIndex     = 0;
    uint32_t callerIntoParamIndex = 0;
    uint32_t calleeIntoParamIndex = 0;

    SemaEscapeSummaryEdgeKind kind           = SemaEscapeSummaryEdgeKind::ReturnToReturn;
    bool                      callerIndirect = false;
    bool                      calleeIndirect = false;

    // Owned payload borrows propagate, but freeing the payload does not free
    // the owner itself and must not propagate FREES.
    bool viaOwnedPayload = false;

    // A field-carried borrow propagates retention, but freeing its separate
    // carrier allocation does not free the parameter it carries.
    bool viaStoredField = false;

    // The argument was read out of the caller parameter's box as 'parameter[]'. A callee
    // freeing it frees what the box holds: the caller's INDIRECT frees summary.
    bool viaParameterPointee = false;

    // First field used to reach the callee argument from the caller parameter. A callee
    // reallocation then affects this field, whatever nested payload it moves internally.
    const SymbolVariable* callerProjectionField = nullptr;

    // Intermediate calls must return this parameter's borrow before the outer
    // summary can apply. Storage effects additionally require every result to alias
    // the preceding argument; a fresh carrier only forwards the lifetime dependency.
    std::vector<SemaEscapeDeferredGuard> returnGuards;
};

// One unresolved release forwarding, reduced to what closing the module's frees summaries needs.
struct SemaEscapeFreesForwarding
{
    SymbolFunction*       caller           = nullptr;
    const SymbolFunction* callee           = nullptr;
    uint32_t              callerParamIndex = 0;
    uint32_t              calleeParamIndex = 0;
    bool                  callerIndirect   = false;
    bool                  calleeIndirect   = false;
};

// Only release-forwarding edges propagate frees: either directly through the
// passed parameter or indirectly through the contents of its box.
inline bool isFreeForwardingEscapeSummaryEdge(const SemaEscapeSummaryEdge& edge)
{
    if (!edge.caller || !edge.callee || edge.kind != SemaEscapeSummaryEdgeKind::StoresToStores || edge.viaOwnedPayload)
        return false;

    return edge.callerIndirect ? edge.viaParameterPointee : !edge.calleeIndirect && !edge.viaStoredField;
}

// Capture opaque-call argument borrows before their escape is known. Checks
// gain diagnostic context and edges gain their kind when the borrow escapes.
// A local-bound result retains this snapshot until that local later escapes.
struct SemaEscapeDeferredCallSnapshot
{
    std::vector<SemaEscapeDeferredCheck> checks;
    std::vector<SemaEscapeSummaryEdge>   edges;
};

SWC_END_NAMESPACE();
