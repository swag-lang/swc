// Sema/Type/SemaCast.h
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
    AstNodeRef   nodeRef;
    TypeRef      srcTypeRef;
    TypeRef      dstTypeRef;
    Utf8         valueStr;

    void reset(AstNodeRef errorNodeRef)
    {
        *this      = CastFailure{};
        diagId     = DiagnosticId::None;
        noteId     = DiagnosticId::None;
        nodeRef    = errorNodeRef;
        srcTypeRef = TypeRef{};
        dstTypeRef = TypeRef{};
        valueStr.clear();
    }

    void set(AstNodeRef errorNodeRef, DiagnosticId d, TypeRef src, TypeRef dst)
    {
        *this      = CastFailure{};
        diagId     = d;
        nodeRef    = errorNodeRef;
        srcTypeRef = src;
        dstTypeRef = dst;
    }

    void setValueNote(AstNodeRef errorNodeRef, DiagnosticId d, TypeRef src, TypeRef dst, std::string_view value, DiagnosticId note)
    {
        *this      = CastFailure{};
        diagId     = d;
        nodeRef    = errorNodeRef;
        srcTypeRef = src;
        dstTypeRef = dst;
        valueStr   = std::string(value);
        noteId     = note;
    }
};

struct CastFoldContext
{
    ConstantRef  srcConstRef;
    ConstantRef* outConstRef; // optional (can be nullptr)
};

struct CastContext
{
    CastKind    kind;
    CastFlags   flags = CastFlagsE::Zero;
    AstNodeRef  errorNodeRef;
    CastFailure failure;

    // nullptr => not folding. If set, cast ops may produce a folded constant.
    CastFoldContext* fold = nullptr;

    CastContext() = delete;
    explicit CastContext(CastKind kind) :
        kind(kind)
    {
    }

    void resetFailure() { failure.reset(errorNodeRef); }
    void fail(DiagnosticId d, TypeRef src, TypeRef dst) { failure.set(errorNodeRef, d, src, dst); }
    void failValueNote(DiagnosticId d, TypeRef src, TypeRef dst, std::string_view value, DiagnosticId note) { failure.setValueNote(errorNodeRef, d, src, dst, value, note); }
};

namespace SemaCast
{
    bool        analyseCast(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef dstTypeRef);
    bool        foldConstantCast(Sema& sema, CastContext& castCtx, ConstantRef srcConstRef, TypeRef dstTypeRef, ConstantRef& outConstRef);
    void        emitCastFailure(Sema& sema, const CastFailure& f);
    bool        castAllowed(Sema& sema, CastContext& castCtx, TypeRef srcTypeRef, TypeRef targetTypeRef);
    ConstantRef castConstant(Sema& sema, CastContext& castCtx, ConstantRef cstRef, TypeRef targetTypeRef);

    bool promoteConstants(Sema& sema, const SemaNodeViewList& ops, ConstantRef& leftRef, ConstantRef& rightRef, bool force32BitInts = false);
};

SWC_END_NAMESPACE()
