// Sema/Type/SemaCast.h
#pragma once
#include "Parser/AstNode.h"
#include "Report/Diagnostic.h"
#include "Sema/Constant/ConstantValue.h"

SWC_BEGIN_NAMESPACE()

struct CastContext;
struct CastFailure;
struct SemaNodeView;
class Sema;

namespace SemaCast
{
    bool castAllowed(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    void emitCastFailure(Sema& sema, const CastFailure& f);

    void foldConstantIdentity(CastContext& castCtx);
    bool foldConstantBitCast(Sema& sema, CastContext& castCtx, TypeRef dstTypeRef, const TypeInfo& dstType, const TypeInfo& srcType);
    bool foldConstantBoolToIntLike(Sema& sema, CastContext& castCtx, TypeRef dstTypeRef);
    bool foldConstantIntLikeToBool(Sema& sema, CastContext& castCtx);
    bool foldConstantIntLikeToIntLike(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    bool foldConstantIntLikeToFloat(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    bool foldConstantFloatToIntLike(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    bool foldConstantFloatToFloat(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);

    ConstantRef castConstant(Sema& sema, CastContext& castCtx, ConstantRef cstRef, TypeRef targetTypeRef);
    bool        promoteConstants(Sema& sema, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView, ConstantRef& leftCstRef, ConstantRef& rightCstRef, bool force32BitInts = false);

    AstNodeRef createImplicitCast(Sema& sema, TypeRef dstTypeRef, AstNodeRef nodeRef);

    void promoteEnumToUnderlying(Sema& sema, SemaNodeView& nodeView);
    void promoteTypeToTypeValue(Sema& sema, SemaNodeView& nodeView);
    void promoteForEquality(Sema& sema, SemaNodeView& leftNodeView, SemaNodeView& rightNodeView);
}

SWC_END_NAMESPACE()
