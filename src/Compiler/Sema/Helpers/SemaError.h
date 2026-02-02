#pragma once
#include "Compiler/Parser/Ast/AstNode.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class Symbol;

namespace SemaError
{
    Diagnostic report(Sema& sema, DiagnosticId id, AstNodeRef nodeRef);
    Diagnostic report(Sema& sema, DiagnosticId id, SourceLocation loc);
    Diagnostic report(Sema& sema, DiagnosticId id, SourceViewRef srcViewRef, TokenRef tokRef);

    Result raise(Sema& sema, DiagnosticId id, SourceLocation loc);
    Result raise(Sema& sema, DiagnosticId id, SourceViewRef srcViewRef, TokenRef tokRef);
    Result raise(Sema& sema, DiagnosticId id, AstNodeRef nodeRef);

    Diagnostic reportCannotCast(Sema& sema, AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef);

    Result raiseInvalidType(Sema& sema, AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef);
    Result raiseRequestedTypeFam(Sema& sema, AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef);
    Result raiseLiteralOverflow(Sema& sema, AstNodeRef nodeRef, const ConstantValue& literal, TypeRef targetTypeRef);
    Result raiseExprNotConst(Sema& sema, AstNodeRef nodeRef);
    Result raiseBinaryOperandType(Sema& sema, const AstNode& nodeOp, AstNodeRef nodeValueRef, TypeRef targetTypeRef);
    Result raiseUnaryOperandType(Sema& sema, const AstNode& nodeOp, AstNodeRef nodeValueRef, TypeRef targetTypeRef);
    Result raiseInternal(Sema& sema, const AstNode& node);
    Result raiseAlreadyDefined(Sema& sema, const Symbol* symbol, const Symbol* otherSymbol);
    Result raiseGhosting(Sema& sema, const Symbol* symbol, const Symbol* otherSymbol);
    Result raiseAmbiguousSymbol(Sema& sema, AstNodeRef nodeRef, std::span<const Symbol*> symbols);
    Result raiseLiteralTooBig(Sema& sema, AstNodeRef nodeRef, const ConstantValue& literal);
    Result raiseDivZero(Sema& sema, const AstNode& nodeOp, AstNodeRef nodeValueRef);
    Result raisePointerArithmeticValuePointer(Sema& sema, const AstNode& nodeOp, AstNodeRef nodeValueRef, TypeRef targetTypeRef);
    Result raisePointerArithmeticVoidPointer(Sema& sema, const AstNode& nodeOp, AstNodeRef nodeValueRef, TypeRef targetTypeRef);
    Result raiseInvalidOpEnum(Sema& sema, const AstNode& nodeOp, AstNodeRef nodeValueRef, TypeRef targetTypeRef);
    Result raiseTypeNotIndexable(Sema& sema, AstNodeRef nodeRef, TypeRef typeRef);
    Result raiseIndexOutOfRange(Sema& sema, int64_t index, size_t maxCount, AstNodeRef nodeRef);
}

SWC_END_NAMESPACE();
