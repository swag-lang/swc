// Sema/Type/SemaCast.h
#pragma once
#include "Parser/AstNode.h"
#include "Report/Diagnostic.h"
#include "Sema/Constant/ConstantValue.h"

SWC_BEGIN_NAMESPACE()

struct CastContext;
struct CastFailure;
struct SemaNodeViewList;
class Sema;

namespace SemaCast
{
    bool castAllowed(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    void emitCastFailure(Sema& sema, const CastFailure& f);

    void        foldConstantIdentity(CastContext& castCtx);
    bool        foldConstantBitCast(Sema& sema, CastContext& castCtx, TypeRef dstTypeRef, const TypeInfo& dstType, const TypeInfo& srcType);
    bool        foldConstantBoolToIntLike(Sema& sema, CastContext& castCtx, const TypeInfo& dstType);
    bool        foldConstantIntLikeToBool(Sema& sema, CastContext& castCtx);
    bool        foldConstantIntLikeToIntLike(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef, const TypeInfo& dstType);
    bool        foldConstantIntLikeToFloat(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef, const TypeInfo& dstType);
    bool        foldConstantFloatToIntLike(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef, const TypeInfo& dstType);
    bool        foldConstantFloatToFloat(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef, const TypeInfo& dstType);
    ConstantRef castConstant(Sema& sema, CastContext& castCtx, ConstantRef cstRef, TypeRef targetTypeRef);
    bool        promoteConstants(Sema& sema, const SemaNodeViewList& ops, ConstantRef& leftCstRef, ConstantRef& rightCstRef, bool force32BitInts = false);
};

SWC_END_NAMESPACE()
