#pragma once
#include "Compiler/Sema/Cast/CastFailure.h"
#include "Compiler/Sema/Constant/ConstantValue.h"

SWC_BEGIN_NAMESPACE();

struct SemaNodeView;
class Sema;
class Diagnostic;

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

    void fail(DiagnosticId d, TypeRef srcRef, TypeRef dstRef, std::string_view value = "", DiagnosticId note = DiagnosticId::None);

    bool        isConstantFolding() const { return srcConstRef.isValid(); }
    ConstantRef constantFoldingSrc() const { return srcConstRef; }
    ConstantRef constantFoldingResult() const { return outConstRef; }

    void setConstantFoldingSrc(ConstantRef v)
    {
        srcConstRef = v;
        outConstRef = v;
    }

    void setConstantFoldingResult(ConstantRef v)
    {
        outConstRef = v;
    }
};

struct Cast
{
    static Result  castAllowed(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static TypeRef castAllowedBothWays(Sema& sema, TypeRef srcTypeRef, TypeRef dstTypeRef, CastKind castKind = CastKind::Implicit);
    static Result  cast(Sema& sema, SemaNodeView& view, TypeRef dstTypeRef, CastKind castKind, CastFlags castFlags = CastFlagsE::Zero);
    static Result  emitCastFailure(Sema& sema, const CastFailure& f);

    static Result promoteConstants(Sema& sema, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView, ConstantRef& leftCstRef, ConstantRef& rightCstRef, bool force32BitInts = false);
    static Result concretizeConstant(Sema& sema, ConstantRef& result, AstNodeRef nodeOwnerRef, ConstantRef cstRef, TypeInfo::Sign hintSign, bool force32BitInts = false);

    static AstNodeRef createImplicitCast(Sema& sema, TypeRef dstTypeRef, AstNodeRef nodeRef);
    static void       convertEnumToUnderlying(Sema& sema, SemaNodeView& nodeView);

private:
    static Result castIdentity(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castBit(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castBoolToIntLike(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castToBool(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castIntLikeToIntLike(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castIntLikeToFloat(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castFloatToIntLike(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castToIntLike(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castFloatToFloat(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castToFloat(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castFromEnum(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castFromNull(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castFromUndefined(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castToReference(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castPointerToPointer(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castToPointer(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castToSlice(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castToArray(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castFromTypeValue(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castToFromTypeInfo(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castToString(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castToCString(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castToVariadic(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castToInterface(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castFromAny(const Sema& sema, const CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);

    static void foldConstantIdentity(CastContext& castCtx);
    static bool foldConstantBitCast(Sema& sema, CastContext& castCtx, TypeRef dstTypeRef, const TypeInfo& dstType, const TypeInfo& srcType);
    static bool foldConstantBoolToIntLike(Sema& sema, CastContext& castCtx, TypeRef dstTypeRef);
    static bool foldConstantIntLikeToBool(Sema& sema, CastContext& castCtx);
    static bool foldConstantIntLikeToIntLike(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static bool foldConstantIntLikeToFloat(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static bool foldConstantFloatToIntLike(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static bool foldConstantFloatToFloat(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);

    static Result  castConstant(Sema& sema, ConstantRef& result, CastContext& castCtx, ConstantRef cstRef, TypeRef targetTypeRef);
    static Result  castConstant(Sema& sema, ConstantRef& result, ConstantRef cstRef, TypeRef targetTypeRef, AstNodeRef errorNodeRef, CastKind castKind = CastKind::Implicit);
    static TypeRef castAllowedBothWays(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static bool    concretizeConstant(Sema& sema, ConstantRef& result, ConstantRef cstRef, TypeInfo::Sign hintSign, bool force32BitInts = false);

    static Result castToStruct(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
};

SWC_END_NAMESPACE();
