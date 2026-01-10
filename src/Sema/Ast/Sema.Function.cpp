#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Helpers/SemaCheck.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaHelpers.h"
#include "Sema/Symbol/Symbol.Impl.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE();

Result AstFunctionParamMe::semaPreNode(Sema& sema) const
{
    if (!sema.frame().impl())
        return SemaError::raise(sema, DiagnosticId::sema_err_tok_outside_impl, sema.curNodeRef());

    const SymbolImpl*   symImpl   = sema.frame().impl()->symMap()->safeCast<SymbolImpl>();
    const SymbolStruct* symStruct = symImpl->structSym();

    auto& sym = SemaHelpers::registerSymbol<SymbolVariable>(sema, *this, tokRef());

    TypeInfoFlags typeFlags = TypeInfoFlagsE::Zero;
    if (hasFlag(AstFunctionParamMeFlagsE::Const))
        typeFlags.add(TypeInfoFlagsE::Const);
    const TypeRef typeRef = sema.typeMgr().addType(TypeInfo::makeValuePointer(symStruct->typeRef(), typeFlags));
    sym.setTypeRef(typeRef);

    return Result::Continue;
}

Result AstFunctionDecl::semaPreDecl(Sema& sema) const
{
    SymbolFunction& sym = SemaHelpers::registerSymbol<SymbolFunction>(sema, *this, tokNameRef);
    sym.setFuncFlags(this->flags());
    return Result::SkipChildren;
}

Result AstFunctionDecl::semaPreNode(Sema& sema) const
{
    if (sema.enteringState())
        SemaHelpers::declareSymbol(sema, *this);

    const SymbolFunction& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolFunction>();
    if (sym.isMethod() && !sema.frame().impl() && !sema.curScope().isInterface())
    {
        const SourceView& srcView   = sema.srcView(srcViewRef());
        const TokenRef    mtdTokRef = srcView.findLeftFrom(tokNameRef, {TokenId::KwdMtd});
        return SemaError::raise(sema, DiagnosticId::sema_err_method_outside_impl, srcViewRef(), mtdTokRef);
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

        if (sym.isMethod())
        {
            IdentifierRef idMe = sema.idMgr().addIdentifier("me");
            if (sym.parameters().empty() || sym.parameters()[0]->idRef() != idMe)
            {
                const Symbol* symStruct = nullptr;
                if (sema.frame().impl())
                    symStruct = sema.frame().impl()->structSym();
                else if (sema.curScope().parent() && sema.curScope().parent()->isInterface())
                    symStruct = sema.curScope().parent()->symMap();

                if (symStruct)
                {
                    auto&           ctx   = sema.ctx();
                    SymbolVariable* symMe = Symbol::make<SymbolVariable>(ctx, nullptr, tokRef(), idMe, SymbolFlagsE::Zero);
                    const TypeRef   typeRef = sema.typeMgr().addType(TypeInfo::makeValuePointer(symStruct->typeRef(), TypeInfoFlagsE::Zero));
                    symMe->setTypeRef(typeRef);

                    sym.addParameter(symMe);
                    if (sym.parameters().size() > 1)
                    {
                        for (size_t i = sym.parameters().size() - 1; i > 0; --i)
                            sym.parameters()[i] = sym.parameters()[i - 1];
                        sym.parameters()[0] = symMe;
                    }

                    sym.addSymbol(ctx, symMe, true);
                }
            }
        }
    }
    else if (childRef == nodeBodyRef)
    {
        SymbolFunction& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolFunction>();
        RESULT_VERIFY(SemaCheck::checkSignature(sema, sym.parameters(), false));
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
