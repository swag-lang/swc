#pragma once
#include "Compiler/Sema/Cast/CastFailure.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;

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
};
using CastFlags = EnumFlags<CastFlagsE>;

struct CastRequest
{
    CastKind        kind                 = CastKind::Implicit;
    CastFlags       flags                = CastFlagsE::Zero;
    AstNodeRef      errorNodeRef         = AstNodeRef::invalid();
    SourceCodeRef   errorCodeRef         = SourceCodeRef::invalid();
    ConstantRef     srcConstRef          = ConstantRef::invalid();
    ConstantRef     outConstRef          = ConstantRef::invalid();
    SymbolFunction* selectedStructOpCast = nullptr;
    CastFailure     failure{};

    // True during overload-resolution probing: we only need the allow/deny + rank decision,
    // not the folded constant. When set, post-decision result materialization (whole-value
    // byte lowering, aggregate/array fold, throwaway type interning) is skipped -- the chosen
    // overload re-runs the real cast afterwards. Constant-value-dependent *decisions* still
    // run, because srcConstRef stays set (isConstantFolding() is unaffected).
    bool probing = false;

    CastRequest() = delete;
    explicit CastRequest(CastKind kind);

    Result fail(DiagnosticId d, TypeRef srcRef, TypeRef dstRef, std::string_view value = "", DiagnosticId note = DiagnosticId::None);

    bool        isConstantFolding() const { return srcConstRef.isValid(); }
    // Whether the folded constant *result* should actually be materialized. False while probing.
    bool        materializeConstantResult() const { return srcConstRef.isValid() && !probing; }
    ConstantRef constantFoldingSrc() const { return srcConstRef; }
    ConstantRef constantFoldingResult() const { return outConstRef; }
    void        setConstantFoldingSrc(ConstantRef v);
    void        setConstantFoldingResult(ConstantRef v);
};

SWC_END_NAMESPACE();
