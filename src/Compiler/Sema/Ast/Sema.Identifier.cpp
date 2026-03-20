#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaSymbolLookup.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/Symbol.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    TypeRef unwrapLambdaBindingType(TaskContext& ctx, TypeRef typeRef)
    {
        while (typeRef.isValid())
        {
            const TypeInfo& typeInfo  = ctx.typeMgr().get(typeRef);
            const TypeRef   unwrapped = typeInfo.unwrap(ctx, TypeRef::invalid(), TypeExpandE::Alias | TypeExpandE::Enum);
            if (unwrapped.isValid())
            {
                typeRef = unwrapped;
                continue;
            }

            if (typeInfo.isReference())
            {
                typeRef = typeInfo.payloadTypeRef();
                continue;
            }

            break;
        }

        return typeRef;
    }

    const SymbolFunction* resolveLambdaBindingFunction(Sema& sema)
    {
        const std::span<const TypeRef> bindingTypes = sema.frame().bindingTypes();
        for (size_t bindingIndex = bindingTypes.size(); bindingIndex > 0; --bindingIndex)
        {
            const TypeRef bindingTypeRef = unwrapLambdaBindingType(sema.ctx(), bindingTypes[bindingIndex - 1]);
            if (!bindingTypeRef.isValid())
                continue;

            const TypeInfo& bindingType = sema.typeMgr().get(bindingTypeRef);
            if (bindingType.isFunction())
                return &bindingType.payloadSymFunction();
        }

        return nullptr;
    }

    bool requiresExplicitCaptureList(Sema& sema, const SymbolFunction& function)
    {
        const AstNode* decl = function.decl();
        if (!decl)
            return false;

        if (decl->is(AstNodeId::ClosureExpr))
            return true;
        if (decl->isNot(AstNodeId::FunctionExpr))
            return false;

        const SymbolFunction* bindingFunction = resolveLambdaBindingFunction(sema);
        return bindingFunction && bindingFunction->isClosure();
    }

    bool requiresExplicitClosureCapture(Sema& sema, const Symbol& symbol)
    {
        const SymbolFunction* currentFn = SemaHelpers::currentFunction(sema);
        if (!currentFn || !requiresExplicitCaptureList(sema, *currentFn))
            return false;

        const AstNode* parent = sema.visit().parentNode();
        if (parent && parent->is(AstNodeId::ClosureArgument))
            return false;

        if (!symbol.isVariable())
            return false;

        const auto& symVar = symbol.cast<SymbolVariable>();
        if (symVar.ownerSymMap() == currentFn)
            return false;
        if (symVar.hasGlobalStorage())
            return false;
        if (!(symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter) ||
              symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal) ||
              symVar.isClosureCapture()))
            return false;

        return true;
    }

}

Result AstIdentifier::semaPostNode(Sema& sema) const
{
    // Can be forced to false in case of an identifier inside a #defined
    // @CompilerNotDefined
    const SemaNodeView view = sema.curViewConstant();
    if (view.cstRef().isValid())
        return Result::Continue;

    const IdentifierRef idRef = SemaHelpers::resolveIdentifier(sema, codeRef());

    // Parser tags the callee expression when building a call: `foo()`.
    const bool allowOverloadSet = hasFlag(AstIdentifierFlagsE::CallCallee);

    MatchContext lookUpCxt;
    lookUpCxt.codeRef = codeRef();

    const Result ret = Match::match(sema, lookUpCxt, idRef);
    if (ret == Result::Pause && hasFlag(AstIdentifierFlagsE::InCompilerDefined))
        return sema.waitCompilerDefined(idRef, codeRef());
    SWC_RESULT(ret);

    SWC_RESULT(SemaSymbolLookup::bindResolvedSymbols(sema, sema.curNodeRef(), allowOverloadSet, lookUpCxt.symbols().span()));
    if (const Symbol* sym = sema.curViewSymbol().sym(); sym && requiresExplicitClosureCapture(sema, *sym))
        return SemaError::raise(sema, DiagnosticId::sema_err_closure_capture_missing, sema.curNodeRef());
    return Result::Continue;
}

SWC_END_NAMESPACE();
