#pragma once
#include "Compiler/Parser/Ast/AstNode.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class Symbol;

namespace SemaError
{
    enum class ReportLocation
    {
        Token,
        Children,
    };

    void addSpan(Sema& sema, DiagnosticElement& element, AstNodeRef nodeRef, const Utf8& message = "", DiagnosticSeverity severity = DiagnosticSeverity::Note);

    Diagnostic report(Sema& sema, DiagnosticId id, AstNodeRef atNodeRef);
    Diagnostic report(Sema& sema, DiagnosticId id, AstNodeRef atNodeRef, ReportLocation location);
    Diagnostic report(Sema& sema, DiagnosticId id, const SourceCodeRef& codeRef);

    Result raise(Sema& sema, DiagnosticId id, const SourceCodeRef& codeRef);
    Result raise(Sema& sema, DiagnosticId id, AstNodeRef nodeRef);
    Result raise(Sema& sema, DiagnosticId id, AstNodeRef nodeRef, ReportLocation location);

    Diagnostic reportCannotCast(Sema& sema, AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef);

    Result raiseInvalidType(Sema& sema, AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef);
    Result raiseRequestedTypeFam(Sema& sema, AstNodeRef nodeRef, TypeRef srcTypeRef, TypeRef targetTypeRef);
    Result raiseLiteralOverflow(Sema& sema, AstNodeRef nodeRef, const ConstantValue& literal, TypeRef targetTypeRef);
    Result raiseExprNotConst(Sema& sema, AstNodeRef nodeRef);
    Result raiseBinaryOperandType(Sema& sema, AstNodeRef nodeOpRef, AstNodeRef nodeValueRef, TypeRef targetTypeRef);
    Result raiseUnaryOperandType(Sema& sema, AstNodeRef nodeOpRef, AstNodeRef nodeValueRef, TypeRef targetTypeRef);
    Result raiseInternal(Sema& sema, AstNodeRef nodeRef);
    Result raiseAlreadyDefined(Sema& sema, const Symbol* symbol, const Symbol* otherSymbol);
    Result raiseGhosting(Sema& sema, const Symbol* symbol, const Symbol* otherSymbol);
    Result raiseAmbiguousSymbol(Sema& sema, AstNodeRef nodeRef, std::span<const Symbol*> symbols);
    Result raiseLiteralTooBig(Sema& sema, AstNodeRef nodeRef, const ConstantValue& literal);
    Result raiseDivZero(Sema& sema, AstNodeRef nodeOpRef, AstNodeRef nodeValueRef);
    Result raisePointerArithmeticValuePointer(Sema& sema, AstNodeRef nodeOpRef, AstNodeRef nodeValueRef, TypeRef targetTypeRef);
    Result raisePointerArithmeticVoidPointer(Sema& sema, AstNodeRef nodeOpRef, AstNodeRef nodeValueRef, TypeRef targetTypeRef);
    Result raiseInvalidOpEnum(Sema& sema, AstNodeRef nodeOpRef, AstNodeRef nodeValueRef, TypeRef targetTypeRef);
    Result raiseTypeNotIndexable(Sema& sema, AstNodeRef atNodeRef, TypeRef typeRef);
    Result raiseIndexOutOfRange(Sema& sema, AstNodeRef atNodeRef, int64_t index, size_t maxCount);
}

SWC_END_NAMESPACE();
