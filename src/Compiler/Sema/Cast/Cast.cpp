#include "pch.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

void CastFailure::set(AstNodeRef errorNodeRef, DiagnosticId d, TypeRef srcRef, TypeRef dstRef, std::string_view value, DiagnosticId note)
{
    *this      = CastFailure{};
    diagId     = d;
    nodeRef    = errorNodeRef;
    srcTypeRef = srcRef;
    dstTypeRef = dstRef;
    valueStr   = std::string(value);
    noteId     = note;
}

bool CastFailure::hasArgument(std::string_view name) const
{
    for (const auto& a : arguments)
    {
        if (a.name == name)
            return true;
    }
    return false;
}

void CastFailure::applyArguments(Diagnostic& diag) const
{
    if (srcTypeRef.isValid())
        diag.addArgument(Diagnostic::ARG_TYPE, srcTypeRef);
    if (dstTypeRef.isValid())
        diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, dstTypeRef);
    if (optTypeRef.isValid())
        diag.addArgument(Diagnostic::ARG_OPT_TYPE, optTypeRef);
    if (!valueStr.empty() && !hasArgument(Diagnostic::ARG_VALUE))
        diag.addArgument(Diagnostic::ARG_VALUE, valueStr);
    for (const auto& arg : arguments)
        diag.addArgument(arg.name, arg.val);
}

void CastFailure::applyArguments(DiagnosticElement& element) const
{
    if (srcTypeRef.isValid())
        element.addArgument(Diagnostic::ARG_TYPE, srcTypeRef);
    if (dstTypeRef.isValid())
        element.addArgument(Diagnostic::ARG_REQUESTED_TYPE, dstTypeRef);
    if (optTypeRef.isValid())
        element.addArgument(Diagnostic::ARG_OPT_TYPE, optTypeRef);
    if (!valueStr.empty() && !hasArgument(Diagnostic::ARG_VALUE))
        element.addArgument(Diagnostic::ARG_VALUE, valueStr);
    for (const auto& arg : arguments)
        element.addArgument(arg.name, arg.val);
}

CastContext::CastContext(CastKind kind) :
    kind(kind)
{
}

void CastContext::fail(DiagnosticId d, TypeRef srcRef, TypeRef dstRef, std::string_view value, DiagnosticId note)
{
    failure.set(errorNodeRef, d, srcRef, dstRef, value, note);
}

Result Cast::emitCastFailure(Sema& sema, const CastFailure& f)
{
    SWC_ASSERT(f.nodeRef.isValid());
    auto diag = SemaError::report(sema, f.diagId, f.nodeRef);
    f.applyArguments(diag);
    diag.addNote(f.noteId);
    diag.report(sema.ctx());
    return Result::Error;
}

AstNodeRef Cast::createImplicitCast(Sema& sema, TypeRef dstTypeRef, AstNodeRef nodeRef)
{
    const AstNode& node               = sema.node(nodeRef);
    auto [substNodeRef, substNodePtr] = sema.ast().makeNode<AstNodeId::ImplicitCastExpr>(node.tokRef());
    substNodePtr->nodeExprRef         = nodeRef;
    sema.setSubstitute(nodeRef, substNodeRef);
    sema.setType(substNodeRef, dstTypeRef);
    sema.setIsValue(*substNodePtr);
    return substNodeRef;
}

SWC_END_NAMESPACE();
