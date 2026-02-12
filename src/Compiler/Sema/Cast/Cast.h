#pragma once
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/CastRequest.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

struct SemaNodeView;
class Sema;
class Diagnostic;

struct Cast
{
    static Result  castAllowed(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static TypeRef castAllowedBothWays(Sema& sema, TypeRef srcTypeRef, TypeRef dstTypeRef, CastKind castKind = CastKind::Implicit);
    static Result  cast(Sema& sema, SemaNodeView& view, TypeRef dstTypeRef, CastKind castKind, CastFlags castFlags = CastFlagsE::Zero);
    static Result  emitCastFailure(Sema& sema, const CastFailure& f);

    static Result promoteConstants(Sema& sema, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView, ConstantRef& leftCstRef, ConstantRef& rightCstRef, bool force32BitInts = false);
    static Result concretizeConstant(Sema& sema, ConstantRef& result, AstNodeRef nodeOwnerRef, ConstantRef cstRef, TypeInfo::Sign hintSign, bool force32BitInts = false);

    static AstNodeRef createCast(Sema& sema, TypeRef dstTypeRef, AstNodeRef nodeRef, AstCastExprFlagsE castFlags = AstCastExprFlagsE::Zero);
    static void       convertEnumToUnderlying(Sema& sema, SemaNodeView& nodeView);

private:
    static Result castIdentity(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castBit(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castBoolToIntLike(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castToBool(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castIntLikeToIntLike(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castIntLikeToFloat(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castFloatToIntLike(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castToIntLike(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castFloatToFloat(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castToFloat(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castFromEnum(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castFromNull(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castFromUndefined(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castToReference(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castPointerToPointer(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castToPointer(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castToSlice(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castToArray(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castFromTypeValue(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castToFromTypeInfo(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castToString(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castToCString(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castToVariadic(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castToInterface(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static Result castFromAny(const Sema& sema, const CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef);

    static void foldConstantIdentity(CastRequest& castRequest);
    static bool foldConstantBitCast(Sema& sema, CastRequest& castRequest, TypeRef dstTypeRef, const TypeInfo& dstType, const TypeInfo& srcType);
    static bool foldConstantBoolToIntLike(Sema& sema, CastRequest& castRequest, TypeRef dstTypeRef);
    static bool foldConstantIntLikeToBool(Sema& sema, CastRequest& castRequest);
    static bool foldConstantIntLikeToIntLike(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static bool foldConstantIntLikeToFloat(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static bool foldConstantFloatToIntLike(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static bool foldConstantFloatToFloat(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef);

    static Result  castConstant(Sema& sema, ConstantRef& result, CastRequest& castRequest, ConstantRef cstRef, TypeRef targetTypeRef);
    static Result  castConstant(Sema& sema, ConstantRef& result, ConstantRef cstRef, TypeRef targetTypeRef, AstNodeRef errorNodeRef, CastKind castKind = CastKind::Implicit);
    static TypeRef castAllowedBothWays(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef);
    static bool    concretizeConstant(Sema& sema, ConstantRef& result, ConstantRef cstRef, TypeInfo::Sign hintSign, bool force32BitInts = false);

    static Result castToStruct(Sema& sema, CastRequest& castRequest, TypeRef srcTypeRef, TypeRef dstTypeRef);
};

SWC_END_NAMESPACE();
