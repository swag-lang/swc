#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Lexer/LangSpec.h"
#include "Parser/AstNodes.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaHelpers.h"
#include "Sema/Match/Match.h"

SWC_BEGIN_NAMESPACE();

Result AstStructDecl::semaPreDecl(Sema& sema) const
{
    auto& sym = SemaHelpers::registerSymbol<SymbolStruct>(sema, *this, tokNameRef);

    // Runtime struct
    if (sym.inSwagNamespace(sema.ctx()))
    {
        const auto&         idMgr = sema.idMgr();
        const IdentifierRef idRef = sym.idRef();

        if (idRef == idMgr.nameTypeInfo() ||
            idRef == idMgr.nameTypeInfoNative() ||
            idRef == idMgr.nameTypeInfoPointer() ||
            idRef == idMgr.nameTypeInfoStruct() ||
            idRef == idMgr.nameTypeInfoFunc() ||
            idRef == idMgr.nameTypeInfoEnum() ||
            idRef == idMgr.nameTypeInfoArray() ||
            idRef == idMgr.nameTypeInfoSlice() ||
            idRef == idMgr.nameTypeInfoAlias() ||
            idRef == idMgr.nameTypeInfoVariadic() ||
            idRef == idMgr.nameTypeInfoGeneric() ||
            idRef == idMgr.nameTypeInfoNamespace() ||
            idRef == idMgr.nameTypeInfoCodeBlock())
        {
            sym.addExtraFlag(SymbolStructFlagsE::TypeInfo);
        }
    }

    return Result::SkipChildren;
}

Result AstStructDecl::semaPreNode(Sema& sema) const
{
    if (sema.enteringState())
        SemaHelpers::declareSymbol(sema, *this);
    const Symbol& sym = sema.symbolOf(sema.curNodeRef());
    return Match::ghosting(sema, sym);
}

Result AstStructDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeBodyRef)
    {
        auto& ctx = sema.ctx();

        // Creates symbol with type
        SymbolStruct&  sym           = sema.symbolOf(sema.curNodeRef()).cast<SymbolStruct>();
        const TypeInfo structType    = TypeInfo::makeStruct(&sym);
        const TypeRef  structTypeRef = ctx.typeMgr().addType(structType);
        sym.setTypeRef(structTypeRef);
        sym.setTyped(sema.ctx());

        sema.pushScopeAutoPopOnPostNode(SemaScopeFlagsE::Type);
        sema.curScope().setSymMap(&sym);
    }

    return Result::Continue;
}

Result AstStructDecl::semaPostNode(Sema& sema)
{
    SymbolStruct& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolStruct>();

    // Runtime struct
    if (sym.inSwagNamespace(sema.ctx()))
        sema.typeMgr().registerRuntimeType(sym.idRef(), sym.typeRef());

    RESULT_VERIFY(sym.canBeCompleted(sema));
    sym.computeLayout(sema);
    sym.setCompleted(sema.ctx());
    return Result::Continue;
}

Result AstAnonymousStructDecl::semaPreDecl(Sema& sema) const
{
    SemaHelpers::registerUniqueSymbol<SymbolStruct>(sema, *this, "anonymous_struct");
    return Result::SkipChildren;
}

Result AstAnonymousStructDecl::semaPreNode(Sema& sema) const
{
    if (sema.enteringState())
        SemaHelpers::declareSymbol(sema, *this);
    const Symbol& sym = sema.symbolOf(sema.curNodeRef());
    return Match::ghosting(sema, sym);
}

Result AstAnonymousStructDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeBodyRef)
    {
        auto& ctx = sema.ctx();

        // Creates symbol with type
        SymbolStruct&  sym           = sema.symbolOf(sema.curNodeRef()).cast<SymbolStruct>();
        const TypeInfo structType    = TypeInfo::makeStruct(&sym);
        const TypeRef  structTypeRef = ctx.typeMgr().addType(structType);
        sym.setTypeRef(structTypeRef);
        sym.setTyped(sema.ctx());

        sema.pushScopeAutoPopOnPostNode(SemaScopeFlagsE::Type);
        sema.curScope().setSymMap(&sym);
    }

    return Result::Continue;
}

Result AstAnonymousStructDecl::semaPostNode(Sema& sema)
{
    SymbolStruct& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolStruct>();
    RESULT_VERIFY(sym.canBeCompleted(sema));
    sym.computeLayout(sema);
    sym.setCompleted(sema.ctx());
    sema.setType(sema.curNodeRef(), sym.typeRef());
    return Result::Continue;
}

SWC_END_NAMESPACE();
