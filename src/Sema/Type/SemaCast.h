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

struct CastFailure
{
    DiagnosticId diagId;
    DiagnosticId noteId;
    AstNodeRef   nodeRef;    // where to point the error (usually castCtx.errorNodeRef)
    TypeRef      srcTypeRef; // optional, depends on diag
    TypeRef      dstTypeRef; // optional
    Utf8         valueStr;
};

struct CastContext
{
    CastKind    kind;
    CastFlags   flags = CastFlagsE::Zero;
    AstNodeRef  errorNodeRef;
    CastFailure failure;

    CastContext() = delete;
    explicit CastContext(CastKind kind) :
        kind(kind)
    {
    }
};

enum class CastMode : uint8_t
{
    Check,    // validate only
    Evaluate, // validate + fold if constant is provided
};

namespace SemaCast
{
    bool        analyseCast(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef, CastMode mode, ConstantRef srcConst, ConstantRef* outConst);
    void        emitCastFailure(Sema& sema, const CastFailure& f);
    bool        castAllowed(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef targetTypeRef);
    ConstantRef castConstant(Sema& sema, CastContext& castCtx, ConstantRef cstRef, TypeRef targetTypeRef);
    bool        promoteConstants(Sema& sema, const SemaNodeViewList& ops, ConstantRef& leftRef, ConstantRef& rightRef, bool force32BitInts = false);
};

SWC_END_NAMESPACE()
