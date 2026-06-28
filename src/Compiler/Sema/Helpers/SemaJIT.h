#pragma once
#include "Compiler/Parser/Ast/AstNode.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class SymbolFunction;
struct ResolvedCallArgument;

namespace SemaJIT
{
    void   clearConstCallCache();
    Result prepareFunction(Sema& sema, SymbolFunction& symFn);
    Result runStatement(Sema& sema, SymbolFunction& symFn, AstNodeRef nodeRef);
    Result runStatementImmediate(Sema& sema, SymbolFunction& symFn, AstNodeRef nodeRef);
    Result runExpr(Sema& sema, SymbolFunction& symFn, AstNodeRef nodeExprRef);
    Result runExprImmediate(Sema& sema, SymbolFunction& symFn, AstNodeRef nodeExprRef);
    Result runFunctionResult(Sema& sema, SymbolFunction& symFn, AstNodeRef nodeRef);
    Result tryRunConstCall(Sema& sema, SymbolFunction& calledFn, AstNodeRef callRef, std::span<const ResolvedCallArgument> resolvedArgs, bool forceEvaluation = false);
    Result tryRunConstSetCall(Sema& sema, SymbolFunction& calledFn, AstNodeRef callRef, std::span<const ResolvedCallArgument> resolvedArgs, TypeRef receiverTypeRef, ConstantRef receiverInitCstRef, bool forceEvaluation = false);
}

SWC_END_NAMESPACE();
