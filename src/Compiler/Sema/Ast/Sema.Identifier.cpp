#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/Symbol.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    // A call callee may legitimately bind to an overload set, but only for callable candidates.
    // If at least one callable candidate exists, keep ONLY those callables (ignore non-callables for a call).
    // If no callable candidates exist:
    //   - if there are multiple candidates, it's ambiguous in value space (report here)
    //   - if there is exactly one, bind it and let the call expression report "not callable".
    bool filterCallCalleeCandidates(std::span<const Symbol*> inSymbols, SmallVector<const Symbol*>& outSymbols)
    {
        outSymbols.clear();

        // Currently, "callable" means "function symbol".
        // Extend here later for function pointers/delegates/call-operator types if needed.
        for (const Symbol* s : inSymbols)
        {
            if (s && s->isFunction())
                outSymbols.push_back(s);
        }

        return !outSymbols.empty();
    }

    Result checkAmbiguityAndBindSymbols(Sema& sema, AstNodeRef nodeRef, bool allowOverloadSetForCallCallee, std::span<const Symbol*> foundSymbols)
    {
        const size_t n = foundSymbols.size();

        if (n <= 1)
        {
            sema.setSymbolList(nodeRef, foundSymbols);
            return Result::Continue;
        }

        // Multiple candidates.
        if (!allowOverloadSetForCallCallee)
            return SemaError::raiseAmbiguousSymbol(sema, nodeRef, foundSymbols);

        // Call-callee context: keep only callables if any exist.
        SmallVector<const Symbol*> callables;
        if (filterCallCalleeCandidates(foundSymbols, callables))
        {
            sema.setSymbolList(nodeRef, callables);
            return Result::Continue;
        }

        // No callable candidates and multiple results => true ambiguity (e.g. multiple vars/namespaces/etc.).
        return SemaError::raiseAmbiguousSymbol(sema, nodeRef, foundSymbols);
    }

    bool isParameterSymbol(const SymbolFunction* func, const Symbol* sym)
    {
        if (!func || !sym || !sym->isVariable())
            return false;

        const auto* var = sym->safeCast<SymbolVariable>();
        if (!var)
            return false;

        for (const auto* param : func->parameters())
        {
            if (param == var)
                return true;
        }

        return false;
    }
}

Result AstIdentifier::semaPostNode(Sema& sema) const
{
    // Can be forced to false in case of an identifier inside a #defined
    // @CompilerNotDefined
    const SemaNodeView nodeView(sema, sema.curNodeRef());
    if (nodeView.cstRef.isValid())
        return Result::Continue;

    const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), codeRef());

    // Parser tags the callee expression when building a call: `foo()`.
    const bool allowOverloadSet = hasFlag(AstIdentifierFlagsE::CallCallee);

    MatchContext lookUpCxt;
    lookUpCxt.codeRef = codeRef();

    const Result ret = Match::match(sema, lookUpCxt, idRef);
    if (ret == Result::Pause && hasFlag(AstIdentifierFlagsE::InCompilerDefined))
        return sema.waitCompilerDefined(idRef, codeRef());
    RESULT_VERIFY(ret);

    RESULT_VERIFY(checkAmbiguityAndBindSymbols(sema, sema.curNodeRef(), allowOverloadSet, lookUpCxt.symbols()));

    const SymbolFunction* func = sema.frame().currentFunction();
    if (!func || !sema.hasSymbolList(sema.curNodeRef()))
        return Result::Continue;
    if (allowOverloadSet)
        return Result::Continue;

    const auto symbols = sema.getSymbolList(sema.curNodeRef());
    for (const auto* sym : symbols)
    {
        if (!sym)
            continue;
        if (sym->isConstant() || sym->isEnumValue())
            continue;
        if (isParameterSymbol(func, sym))
            continue;
        if (const AstNode* parent = sema.visit().parentNode())
        {
            if (parent->is(AstNodeId::MemberAccessExpr))
            {
                const auto* member = parent->cast<AstMemberAccessExpr>();
                if (member->nodeRightRef == sema.curNodeRef())
                    continue;
            }
        }

        if (auto* currentFunc = sema.frame().currentFunction())
            currentFunc->markImpure();
        break;
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
