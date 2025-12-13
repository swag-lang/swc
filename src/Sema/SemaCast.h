#pragma once

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

namespace SemaCast
{
    bool        castAllowed(Sema& sema, const CastContext& castCtx, TypeRef srcTypeRef, TypeRef targetTypeRef);
    ConstantRef castConstant(Sema& sema, const CastContext& castCtx, ConstantRef cstRef, TypeRef targetTypeRef);
    bool        promoteConstants(Sema& sema, const SemaNodeViewList& ops, ConstantRef& leftRef, ConstantRef& rightRef, bool force32BitInts = false);
    ConstantRef concretizeConstant(Sema& sema, ConstantRef cstRef, bool& overflow);
};

SWC_END_NAMESPACE()
