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

    const SymbolImpl* symImpl   = sema.frame().impl()->symMap()->safeCast<SymbolImpl>();
    const TypeRef     ownerType = symImpl->ownerKind() == SymbolImplOwnerKind::Struct ? symImpl->symStruct()->typeRef() : symImpl->symEnum()->typeRef();

    auto& sym = SemaHelpers::registerSymbol<SymbolVariable>(sema, *this, tokRef());

    TypeInfoFlags typeFlags = TypeInfoFlagsE::Zero;
    if (hasFlag(AstFunctionParamMeFlagsE::Const))
        typeFlags.add(TypeInfoFlagsE::Const);
    const TypeRef typeRef = sema.typeMgr().addType(TypeInfo::makeValuePointer(ownerType, typeFlags));
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

    SymbolFunction& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolFunction>();
    if (sym.isMethod() && !sema.frame().impl() && !sema.frame().interface())
    {
        const SourceView& srcView   = sema.srcView(srcViewRef());
        const TokenRef    mtdTokRef = srcView.findLeftFrom(tokNameRef, {TokenId::KwdMtd});
        return SemaError::raise(sema, DiagnosticId::sema_err_method_outside_impl, srcViewRef(), mtdTokRef);
    }

    // return SemaMatch::ghosting(sema, sym);

    SemaFrame frame = sema.frame();
    frame.setFunction(&sym);
    sema.pushFrame(frame);

    return Result::Continue;
}

namespace
{
    void addMeParameter(Sema& sema, SymbolFunction& sym)
    {
        if (sema.frame().impl() && sema.frame().impl()->isForStruct())
        {
            const SymbolImpl* symImpl   = sema.frame().impl()->asSymMap()->safeCast<SymbolImpl>();
            const TypeRef     ownerType = symImpl->symStruct()->typeRef();
            auto&             ctx       = sema.ctx();
            SymbolVariable*   symMe     = Symbol::make<SymbolVariable>(ctx, nullptr, TokenRef::invalid(), sema.idMgr().nameMe(), SymbolFlagsE::Zero);
            TypeInfoFlags     typeFlags = TypeInfoFlagsE::Zero;
            if (sym.hasFuncFlag(SymbolFunctionFlagsE::Const))
                typeFlags.add(TypeInfoFlagsE::Const);
            const TypeRef typeRef = sema.typeMgr().addType(TypeInfo::makeValuePointer(ownerType, typeFlags));
            symMe->setTypeRef(typeRef);

            sym.addParameter(symMe);
            sym.addSymbol(ctx, symMe, true);
        }
    }
}

Result AstFunctionDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeParamsRef)
    {
        SymbolFunction& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolFunction>();
        sema.pushScope(SemaScopeFlagsE::Parameters);
        sema.curScope().setSymMap(&sym);
        if (sym.isMethod())
            addMeParameter(sema, sym);
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
    sema.popFrame();
    return Result::Continue;
}

Result AstCallExpr::semaPostNode(Sema& sema)
{
    // TODO
    sema.setConstant(sema.curNodeRef(), sema.cstMgr().cstBool(true));
    return Result::SkipChildren;
}

SWC_END_NAMESPACE();
