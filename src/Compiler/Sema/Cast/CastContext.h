#pragma once
#include "Compiler/Sema/Cast/CastFailure.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

enum class CastKind
{
    LiteralSuffix,
    Implicit,
    Parameter,
    Condition,
    Explicit,
    Promotion,
    Initialization,
    Assignment,
};

enum class CastFlagsE : uint32_t
{
    Zero         = 0,
    BitCast      = 1 << 0,
    NoOverflow   = 1 << 1,
    UnConst      = 1 << 2,
    UfcsArgument = 1 << 3,
};
using CastFlags = EnumFlags<CastFlagsE>;

struct CastContext
{
    CastKind    kind         = CastKind::Implicit;
    CastFlags   flags        = CastFlagsE::Zero;
    AstNodeRef  errorNodeRef = AstNodeRef::invalid();
    ConstantRef srcConstRef  = ConstantRef::invalid();
    ConstantRef outConstRef  = ConstantRef::invalid();
    CastFailure failure{};

    CastContext() = delete;
    explicit CastContext(CastKind kind);

    Result fail(DiagnosticId d, TypeRef srcRef, TypeRef dstRef, std::string_view value = "", DiagnosticId note = DiagnosticId::None);

    bool        isConstantFolding() const { return srcConstRef.isValid(); }
    ConstantRef constantFoldingSrc() const { return srcConstRef; }
    ConstantRef constantFoldingResult() const { return outConstRef; }
    void        setConstantFoldingSrc(ConstantRef v);
    void        setConstantFoldingResult(ConstantRef v);
};

SWC_END_NAMESPACE();
