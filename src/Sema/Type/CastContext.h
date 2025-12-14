#pragma once
#include "Parser/AstNode.h"
#include "Report/DiagnosticDef.h"
#include "Sema/Constant/ConstantValue.h"

SWC_BEGIN_NAMESPACE()

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

struct CastFoldContext
{
    ConstantRef  srcConstRef;
    ConstantRef* outConstRef; // optional (can be nullptr)
};

struct CastFailure
{
    DiagnosticId diagId     = DiagnosticId::None;
    DiagnosticId noteId     = DiagnosticId::None;
    AstNodeRef   nodeRef    = AstNodeRef::invalid();
    TypeRef      srcTypeRef = TypeRef::invalid();
    TypeRef      dstTypeRef = TypeRef::invalid();
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

    void resetFailure()
    {
        failure.reset(errorNodeRef);
    }

    void fail(DiagnosticId d, TypeRef src, TypeRef dst)
    {
        failure.set(errorNodeRef, d, src, dst);
    }

    void failValueNote(DiagnosticId d, TypeRef src, TypeRef dst, std::string_view value, DiagnosticId note)
    {
        failure.setValueNote(errorNodeRef, d, src, dst, value, note);
    }

    bool isFolding() const
    {
        return fold != nullptr && fold->srcConstRef.isValid();
    }

    ConstantRef foldSrc() const
    {
        return fold ? fold->srcConstRef : ConstantRef::invalid();
    }

    void setFoldOut(ConstantRef v) const
    {
        if (fold && fold->outConstRef)
            *fold->outConstRef = v;
    }
};

SWC_END_NAMESPACE()
