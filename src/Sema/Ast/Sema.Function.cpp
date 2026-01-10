#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Helpers/SemaCheck.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaHelpers.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE();

Result AstFunctionParamMe::semaPreDecl(Sema& sema) const
{
    if (!sema.curScope().isImpl())
        return SemaError::raise(sema, DiagnosticId::sema_err_method_outside_impl, sema.curNodeRef());

    const SymbolImpl*   symImpl   = sema.curScope().symMap()->safeCast<SymbolImpl>();
    const SymbolStruct* symStruct = symImpl->structSym();

    auto& sym = SemaHelpers::registerSymbol<SymbolVariable>(sema, *this, tokRef());

    TypeRef       typeRef   = symStruct->typeRef();
    TypeInfoFlags typeFlags = TypeInfoFlagsE::Zero;
    if (hasParserFlag(Const))
        typeFlags.add(TypeInfoFlagsE::Const);
    typeRef = sema.typeMgr().addType(TypeInfo::makeValuePointer(typeRef, typeFlags));
    sym.setTypeRef(typeRef);

    return Result::Continue;
}

Result AstFunctionDecl::semaPreDecl(Sema& sema) const
{
    SymbolFunction& sym = SemaHelpers::registerSymbol<SymbolFunction>(sema, *this, tokNameRef);
    sym.setFuncFlags(parserFlags<AstLambdaType::FlagsE>());
    return Result::SkipChildren;
}

Result AstFunctionDecl::semaPreNode(Sema& sema) const
{
    if (sema.enteringState())
        SemaHelpers::declareSymbol(sema, *this);

    const SymbolFunction& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolFunction>();
    if (sym.isMethod())
    {
        if (!sema.curScope().isImpl())
        {
            const SourceView& srcView   = sema.srcView(srcViewRef());
            const TokenRef    mtdTokRef = srcView.findLeftFrom(tokNameRef, {TokenId::KwdMtd});
            //return SemaError::raise(sema, DiagnosticId::sema_err_method_outside_impl, srcViewRef(), mtdTokRef);
        }
    }

    // return SemaMatch::ghosting(sema, sym);
    return Result::Continue;
}

Result AstFunctionDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeParamsRef)
    {
        SymbolFunction& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolFunction>();
        sema.pushScope(SemaScopeFlagsE::Parameters);
        sema.curScope().setSymMap(&sym);
    }
    else if (childRef == nodeBodyRef)
    {
        SymbolFunction& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolFunction>();
        RESULT_VERIFY(SemaCheck::checkSignature(sema, sym.parameters(), true));
        sym.setTyped(sema.ctx());
        sema.pushScope(SemaScopeFlagsE::Local);
        sema.curScope().setSymMap(&sym);
        return Result::SkipChildren; // TODO
    }

    return Result::Continue;
}

Result AstFunctionDecl::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeParamsRef || childRef == nodeBodyRef)
        sema.popScope();
    return Result::Continue;
}

Result AstFunctionDecl::semaPostNode(Sema& sema)
{
    SymbolFunction& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolFunction>();
    sym.setCompleted(sema.ctx());
    return Result::Continue;
}

Result AstCallExpr::semaPostNode(Sema& sema)
{
    // TODO
    sema.setConstant(sema.curNodeRef(), sema.cstMgr().cstBool(true));
    return Result::SkipChildren;
}

SWC_END_NAMESPACE();
