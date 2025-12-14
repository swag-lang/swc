#pragma once
#include "Parser/AstNode.h"
#include "Report/Diagnostic.h"
#include "Sema/Constant/ConstantValue.h"

SWC_BEGIN_NAMESPACE()

struct SemaNodeViewList;
class Sema;

enum class CastKind
{
    LiteralSuffix,
    Implicit,
    Explicit,
    Promotion,
};

enum class CastFlagsE : uint32_t
{
    Zero       = 0,
    BitCast    = 1 << 0,
    NoOverflow = 1 << 1,
};
using CastFlags = EnumFlags<CastFlagsE>;

struct CastContext
{
    CastKind   kind;
    CastFlags  flags = CastFlagsE::Zero;
    AstNodeRef errorNodeRef;

    CastContext() = delete;
    explicit CastContext(CastKind kind) :
        kind(kind)
    {
    }
};

struct CastFailure
{
    DiagnosticId diagId;
    AstNodeRef   nodeRef;   // where to point the error (usually castCtx.errorNodeRef)
    TypeRef      leftType;  // optional, depends on diag
    TypeRef      rightType; // optional
    TypeRef      typeArg;   // optional (for "invalid type" cases)
};

enum class CastOp : uint8_t
{
    Identity,
    BitCast,
    BoolToIntLike,
    IntLikeToBool,
    IntLikeToIntLike,
    IntLikeToFloat,
    FloatToFloat,
    FloatToIntLike,
};

struct CastPlan
{
    CastOp      op;
    TypeRef     srcType;
    TypeRef     dstType;
    CastContext ctx;
};

using CastPlanOrFailure = std::variant<CastPlan, CastFailure>;

namespace SemaCast
{
    CastPlanOrFailure analyzeCast(Sema& sema, const CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    void              emitCastFailure(Sema& sema, const CastFailure& f);
    bool              castAllowed(Sema& sema, const CastContext& castCtx, TypeRef srcTypeRef, TypeRef targetTypeRef);
    ConstantRef       castConstant(Sema& sema, const CastContext& castCtx, ConstantRef cstRef, TypeRef targetTypeRef);
    bool              promoteConstants(Sema& sema, const SemaNodeViewList& ops, ConstantRef& leftRef, ConstantRef& rightRef, bool force32BitInts = false);
};

SWC_END_NAMESPACE()
