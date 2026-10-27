#pragma once
#include "Compiler/Sema/Cast/CastFailure.h"
#include "Support/Core/Flags.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;
class Sema;

enum class CastKind
{
    LiteralSuffix,
    Implicit,
    Parameter,
    Condition,
    BoolExpr,
    Explicit,
    Promotion,
    Initialization,
    Assignment,
};

enum class CastFlagsE : uint32_t
{
    Zero                 = 0,
    BitCast              = 1 << 0,
    NoOverflow           = 1 << 1,
    UnConst              = 1 << 2,
    UfcsArgument         = 1 << 3,
    FoldedTypedConst     = 1 << 4,
    FromExplicitNode     = 1 << 5,
    LiteralSuffixConsume = 1 << 6,
    ConstSource          = 1 << 7,
    ForceConstEval       = 1 << 8,
    AllowCopyToMoveRef   = 1 << 9,  // call argument: a plain value may bind a '#move' parameter via a temporary copy
    DeducedDestination   = 1 << 10, // 'cast()': explicit, but the destination comes from the context instead of the source
    LateRelease          = 1 << 11, // 'slot = null' on a 'late' slot: the store that returns it to unset
    Try                  = 1 << 12,
    Assume               = 1 << 13,
    Fallible             = 1 << 14,
    NonNullChecked       = 1 << 15, // an explicit cast owns the check or the caller's assumption
    ErasedArgument       = 1 << 16, // argument of an erased generic call: deduction proved its 'T'
};

using CastFlags = EnumFlags<CastFlagsE>;

struct CastRequest
{
    CastKind  kind  = CastKind::Implicit;
    CastFlags flags = CastFlagsE::Zero;

    AstNodeRef    errorNodeRef = AstNodeRef::invalid();
    SourceCodeRef errorCodeRef = SourceCodeRef::invalid();

    ConstantRef srcConstRef = ConstantRef::invalid();
    ConstantRef outConstRef = ConstantRef::invalid();

    SymbolFunction* selectedStructOpCast = nullptr;
    CastFailure     failure{};

    // '#[Swag.Signal]': the static type of the object whose signal receives this callback.
    TypeRef signalOwnerTypeRef = TypeRef::invalid();

    // Overload probing needs the decision and rank, not the folded result.
    // Skip result allocation and type interning; the selected overload casts
    // again. Keep source constants available for value-dependent decisions.
    bool probing = false;

    // A temporary copy can bind a plain value to #move, but ranks below
    // an exact overload match.
    bool usedCopyToMoveRef = false;

    // Widening an infallible callable succeeds, but an overload retaining
    // the infallible type remains preferred.
    bool usedFallibleWidening = false;

    CastRequest() = delete;
    explicit CastRequest(CastKind kind);

    CastRequest makeNested() const
    {
        CastRequest nested(kind);
        nested.flags        = flags;
        nested.errorNodeRef = errorNodeRef;
        nested.errorCodeRef = errorCodeRef;
        nested.probing      = probing;

        return nested;
    }

    Result fail(DiagnosticId d, TypeRef srcRef, TypeRef dstRef, std::string_view value = "", DiagnosticId note = DiagnosticId::None);

    bool isConstantFolding() const { return srcConstRef.isValid(); }

    // Probing inspects constants without materializing their folded results.
    bool materializeConstantResult() const { return srcConstRef.isValid() && !probing; }

    ConstantRef constantFoldingSrc() const { return srcConstRef; }
    ConstantRef constantFoldingResult() const { return outConstRef; }
    void        setConstantFoldingSrc(ConstantRef v);
    void        setConstantFoldingResult(ConstantRef v);

    void applyAutoCast(const Sema& sema, AstNodeRef nodeRef);
};

SWC_END_NAMESPACE();
