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

    Result raise(Sema& sema, DiagnosticId id, SourceViewRef srcViewRef, TokenRef tokRef);
    Result raise(Sema& sema, DiagnosticId id, AstNodeRef nodeRef);

    Diagnostic reportCannotCast(Sema& sema, AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef);

    Result raiseInvalidType(Sema& sema, AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef);
    Result raiseLiteralOverflow(Sema& sema, AstNodeRef nodeRef, const ConstantValue& literal, TypeRef targetTypeRef);
    Result raiseExprNotConst(Sema& sema, AstNodeRef nodeRef);
    Result raiseBinaryOperandType(Sema& sema, const AstNode& nodeOp, AstNodeRef nodeValueRef, TypeRef targetTypeRef);
    Result raiseInternal(Sema& sema, const AstNode& node);
    Result raiseAlreadyDefined(Sema& sema, const Symbol* symbol, const Symbol* otherSymbol);
    Result raiseGhosting(Sema& sema, const Symbol* symbol, const Symbol* otherSymbol);
    Result raiseAmbiguousSymbol(Sema& sema, SourceViewRef srcViewRef, TokenRef tokRef, std::span<const Symbol*> symbols);
    Result raiseLiteralTooBig(Sema& sema, AstNodeRef nodeRef, const ConstantValue& literal);
    Result raiseDivZero(Sema& sema, const AstNode& nodeOp, AstNodeRef nodeValueRef, TypeRef targetTypeRef);
}

SWC_END_NAMESPACE()
