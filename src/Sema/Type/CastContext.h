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
    Utf8         valueStr{};

    void reset(AstNodeRef errorNodeRef);
    void set(AstNodeRef errorNodeRef, DiagnosticId d, TypeRef src, TypeRef dst);
    void setValueNote(AstNodeRef errorNodeRef, DiagnosticId d, TypeRef src, TypeRef dst, std::string_view value, DiagnosticId note);
};

struct CastContext
{
    CastKind         kind;
    CastFlags        flags = CastFlagsE::Zero;
    AstNodeRef       errorNodeRef;
    CastFailure      failure;
    CastFoldContext* fold = nullptr;

    CastContext() = delete;
    explicit CastContext(CastKind kind);

    void        resetFailure();
    void        fail(DiagnosticId d, TypeRef src, TypeRef dst);
    void        failValueNote(DiagnosticId d, TypeRef src, TypeRef dst, std::string_view value, DiagnosticId note);
    bool        isFolding() const;
    ConstantRef foldSrc() const;
    void        setFoldOut(ConstantRef v) const;
};

SWC_END_NAMESPACE()
