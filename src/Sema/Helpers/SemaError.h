#pragma once
#include "Parser/AstNode.h"
#include "Parser/AstVisitResult.h"
#include "Report/Diagnostic.h"
#include "Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE()

class Sema;
class Symbol;

namespace SemaError
{
    Diagnostic report(Sema& sema, DiagnosticId id, AstNodeRef nodeRef);
    Diagnostic report(Sema& sema, DiagnosticId id, SourceViewRef srcViewRef, TokenRef tokRef);

    AstStepResult raise(Sema& sema, DiagnosticId id, SourceViewRef srcViewRef, TokenRef tokRef);
    AstStepResult raise(Sema& sema, DiagnosticId id, AstNodeRef nodeRef);

    Diagnostic reportCannotCast(Sema& sema, AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef);

    AstStepResult raiseInvalidType(Sema& sema, AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef);
    void          raiseCannotCast(Sema& sema, AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef);
    void          raiseLiteralOverflow(Sema& sema, AstNodeRef nodeRef, const ConstantValue& literal, TypeRef targetTypeRef);
    void          raiseLiteralTooBig(Sema& sema, AstNodeRef nodeRef, const ConstantValue& literal);
    void          raiseDivZero(Sema& sema, const AstNode& nodeOp, AstNodeRef nodeValueRef, TypeRef targetTypeRef);
    AstStepResult raiseExprNotConst(Sema& sema, AstNodeRef nodeRef);
    void          raiseBinaryOperandType(Sema& sema, const AstNode& nodeOp, AstNodeRef nodeValueRef, TypeRef targetTypeRef);
    AstStepResult raiseInternal(Sema& sema, const AstNode& node);
    void          raiseAlreadyDefined(Sema& sema, const Symbol* symbol, const Symbol* otherSymbol);
    void          raiseGhosting(Sema& sema, const Symbol* symbol, const Symbol* otherSymbol);
    void          raiseAmbiguousSymbol(Sema& sema, SourceViewRef srcViewRef, TokenRef tokRef, std::span<const Symbol*> symbols);
}

SWC_END_NAMESPACE()
