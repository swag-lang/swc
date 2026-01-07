#pragma once
#include "Parser/AstNode.h"
#include "Report/DiagnosticDef.h"
#include "Sema/Constant/ConstantValue.h"

SWC_BEGIN_NAMESPACE();

enum class CastKind
{
    LiteralSuffix,
    Implicit,
    Explicit,
    Promotion,
    Initialization,
};

enum class CastFlagsE : uint32_t
{
    Zero       = 0,
    BitCast    = 1 << 0,
    NoOverflow = 1 << 1,
    UnConst    = 1 << 2,
};
using CastFlags = EnumFlags<CastFlagsE>;

struct CastFailure
{
    DiagnosticId diagId     = DiagnosticId::None;
    DiagnosticId noteId     = DiagnosticId::None;
    AstNodeRef   nodeRef    = AstNodeRef::invalid();
    TypeRef      srcTypeRef = TypeRef::invalid();
    TypeRef      dstTypeRef = TypeRef::invalid();
    TypeRef      optTypeRef = TypeRef::invalid();
    Utf8         valueStr{};

    void set(AstNodeRef errorNodeRef, DiagnosticId d, TypeRef srcRef, TypeRef dstRef, std::string_view value, DiagnosticId note);
};

struct CastContext
{
    CastKind    kind         = CastKind::Implicit;
    CastFlags   flags        = CastFlagsE::Zero;
    AstNodeRef  errorNodeRef = AstNodeRef::invalid();
    ConstantRef srcConstRef  = ConstantRef::invalid();
    ConstantRef outConstRef  = ConstantRef::invalid();
    CastFailure failure{};

    CastContext() = delete;
    explicit CastContext(CastKind kind);

    void fail(DiagnosticId d, TypeRef srcRef, TypeRef dstRef, std::string_view value = "", DiagnosticId note = DiagnosticId::None);

    bool        isFolding() const { return srcConstRef.isValid(); }
    ConstantRef foldSrc() const { return srcConstRef; }
    void        setFoldSrc(ConstantRef v) { srcConstRef = v; }
    void        setFoldOut(ConstantRef v) { outConstRef = v; }
};

SWC_END_NAMESPACE();
