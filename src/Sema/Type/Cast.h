#pragma once
#include "Parser/AstNode.h"
#include "Report/DiagnosticDef.h"
#include "Sema/Constant/ConstantValue.h"

SWC_BEGIN_NAMESPACE();

struct SemaNodeView;
class Sema;

enum class CastKind
{
    LiteralSuffix,
    Implicit,
    Condition,
    Explicit,
    Promotion,
    Initialization,
};

enum class CastFlagsE : uint32_t
{
    Zero       = 0,
    BitCast    = 1 << 0,
    NoOverflow = 1 << 1,
    UnConst    = 1 << 2,
};
using CastFlags = EnumFlags<CastFlagsE>;

struct CastFailure
{
    DiagnosticId diagId     = DiagnosticId::None;
    DiagnosticId noteId     = DiagnosticId::None;
    AstNodeRef   nodeRef    = AstNodeRef::invalid();
    TypeRef      srcTypeRef = TypeRef::invalid();
    TypeRef      dstTypeRef = TypeRef::invalid();
    TypeRef      optTypeRef = TypeRef::invalid();
    Utf8         valueStr{};

    void set(AstNodeRef errorNodeRef, DiagnosticId d, TypeRef srcRef, TypeRef dstRef, std::string_view value, DiagnosticId note);
};

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

    void fail(DiagnosticId d, TypeRef srcRef, TypeRef dstRef, std::string_view value = "", DiagnosticId note = DiagnosticId::None);

    bool        isConstantFolding() const { return srcConstRef.isValid(); }
    ConstantRef constantFoldingSrc() const { return srcConstRef; }
    ConstantRef constantFoldingResult() const { return outConstRef; }
    void        setConstantFoldingSrc(ConstantRef v) { srcConstRef = v; }
    void        setConstantFoldingResult(ConstantRef v) { outConstRef = v; }
};

namespace Cast
{
    Result  castAllowed(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    TypeRef castAllowedBothWays(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    Result  cast(Sema& sema, SemaNodeView& view, TypeRef dstTypeRef, CastKind castKind);
    Result  emitCastFailure(Sema& sema, const CastFailure& f);
    bool    concretizeConstant(Sema& sema, ConstantRef& result, CastContext& castCtx, ConstantRef cstRef, TypeInfo::Sign hintSign);

    void foldConstantIdentity(CastContext& castCtx);
    bool foldConstantBitCast(Sema& sema, CastContext& castCtx, TypeRef dstTypeRef, const TypeInfo& dstType, const TypeInfo& srcType);
    bool foldConstantBoolToIntLike(Sema& sema, CastContext& castCtx, TypeRef dstTypeRef);
    bool foldConstantIntLikeToBool(Sema& sema, CastContext& castCtx);
    bool foldConstantIntLikeToIntLike(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    bool foldConstantIntLikeToFloat(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    bool foldConstantFloatToIntLike(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    bool foldConstantFloatToFloat(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);

    Result castConstant(Sema& sema, ConstantRef& result, CastContext& castCtx, ConstantRef cstRef, TypeRef targetTypeRef);
    Result promoteConstants(Sema& sema, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView, ConstantRef& leftCstRef, ConstantRef& rightCstRef, bool force32BitInts = false);

    AstNodeRef createImplicitCast(Sema& sema, TypeRef dstTypeRef, AstNodeRef nodeRef);

    void convertEnumToUnderlying(Sema& sema, SemaNodeView& nodeView);
    void convertTypeToTypeValue(Sema& sema, SemaNodeView& nodeView);
    void convertForEquality(Sema& sema, SemaNodeView& leftNodeView, SemaNodeView& rightNodeView);
}

SWC_END_NAMESPACE();
