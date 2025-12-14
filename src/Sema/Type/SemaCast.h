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
    bool analyseCastCore(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);

    void foldConstantIdentity(const CastContext& castCtx);
    bool foldConstantBitCast(Sema& sema, CastContext& castCtx, TypeRef dstTypeRef, const TypeInfo& dstType, const TypeInfo& srcType);
    bool foldConstantBoolToIntLike(Sema& sema, const CastContext& castCtx, const TypeInfo& dstType);
    bool foldConstantIntLikeToBool(Sema& sema, const CastContext& castCtx);
    bool foldConstantIntLikeToIntLike(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef, const TypeInfo& dstType);
    bool foldConstantIntLikeToFloat(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef, const TypeInfo& dstType);
    bool foldConstantFloatToIntLike(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef, const TypeInfo& dstType);
    bool foldConstantFloatToFloat(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef, const TypeInfo& dstType);

    bool        analyseCast(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    void        emitCastFailure(Sema& sema, const CastFailure& f);
    bool        castAllowed(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef targetTypeRef);
    ConstantRef castConstant(Sema& sema, CastContext& castCtx, ConstantRef cstRef, TypeRef targetTypeRef);

    bool promoteConstants(Sema& sema, const SemaNodeViewList& ops, ConstantRef& leftRef, ConstantRef& rightRef, bool force32BitInts = false);
};

SWC_END_NAMESPACE()
