#pragma once
#include "Parser/AstNode.h"
#include "Report/Diagnostic.h"
#include "Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE()

struct AstNode;
class Sema;

namespace SemaError
{
    Diagnostic reportError(Sema& sema, DiagnosticId id, AstNodeRef nodeRef);
    Diagnostic reportError(Sema& sema, DiagnosticId id, SourceViewRef srcViewRef, TokenRef tokRef);
    Diagnostic reportError(Sema& sema, DiagnosticId id, SourceViewRef srcViewRef, TokenRef tokRef, AstNodeRef nodeSpanRef);

    void raiseError(Sema& sema, DiagnosticId id, SourceViewRef srcViewRef, TokenRef tokRef);
    void raiseError(Sema& sema, DiagnosticId id, AstNodeRef nodeRef);

    void raiseInvalidType(Sema& sema, AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef);
    void raiseCannotCast(Sema& sema, AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef);
    void raiseLiteralOverflow(Sema& sema, AstNodeRef nodeRef, const ConstantValue& literal, TypeRef targetTypeRef);
    void raiseLiteralTooBig(Sema& sema, AstNodeRef nodeRef, const ConstantValue& literal);
    void raiseDivZero(Sema& sema, const AstNode& nodeOp, AstNodeRef nodeValueRef, TypeRef targetTypeRef);
    void raiseExprNotConst(Sema& sema, AstNodeRef nodeRef);
    void raiseBinaryOperandType(Sema& sema, const AstNode& nodeOp, AstNodeRef nodeValueRef, TypeRef targetTypeRef);
    void raiseInternalError(Sema& sema, const AstNode& node);
};

SWC_END_NAMESPACE()
