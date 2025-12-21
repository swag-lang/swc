#pragma once
#include "Parser/AstNode.h"
#include "Report/Diagnostic.h"
#include "Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE()

class Sema;
class Symbol;

namespace SemaError
{
    Diagnostic report(Sema& sema, DiagnosticId id, AstNodeRef nodeRef);
    Diagnostic report(Sema& sema, DiagnosticId id, SourceViewRef srcViewRef, TokenRef tokRef);
    Diagnostic report(Sema& sema, DiagnosticId id, SourceViewRef srcViewRef, TokenRef tokRef, AstNodeRef nodeSpanRef);

    void raise(Sema& sema, DiagnosticId id, SourceViewRef srcViewRef, TokenRef tokRef);
    void raise(Sema& sema, DiagnosticId id, AstNodeRef nodeRef);

    Diagnostic reportCannotCast(Sema& sema, AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef);

    void raiseInvalidType(Sema& sema, AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef);
    void raiseCannotCast(Sema& sema, AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef);
    void raiseLiteralOverflow(Sema& sema, AstNodeRef nodeRef, const ConstantValue& literal, TypeRef targetTypeRef);
    void raiseLiteralTooBig(Sema& sema, AstNodeRef nodeRef, const ConstantValue& literal);
    void raiseDivZero(Sema& sema, const AstNode& nodeOp, AstNodeRef nodeValueRef, TypeRef targetTypeRef);
    void raiseExprNotConst(Sema& sema, AstNodeRef nodeRef);
    void raiseBinaryOperandType(Sema& sema, const AstNode& nodeOp, AstNodeRef nodeValueRef, TypeRef targetTypeRef);
    void raiseInternal(Sema& sema, const AstNode& node);
    void raiseSymbolAlreadyDefined(Sema& sema, const Symbol* symbol);
};

SWC_END_NAMESPACE()
