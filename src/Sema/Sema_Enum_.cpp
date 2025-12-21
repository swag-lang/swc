#include "pch.h"

#include "Helpers/SemaMatch.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisitResult.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaFrame.h"
#include "Sema/Helpers/SemaInfo.h"
#include "Sema/Helpers/SemaNodeView.h"
#include "Sema/Sema.h"
#include "Sema/Symbol/Symbols.h"
#include "Symbol/LookupResult.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstEnumDecl::semaPreChild(Sema& sema, const AstNodeRef& childRef)
{
    if (childRef != nodeBodyRef)
        return AstVisitStepResult::Continue;

    auto& ctx = sema.ctx();

    // Check type if specified
    SemaNodeView typeView(sema, nodeTypeRef);
    if (nodeTypeRef.isValid())
    {
        if (!typeView.type->isScalarNumeric())
        {
            SemaError::raise(sema, DiagnosticId::sema_err_invalid_enum_type, nodeTypeRef);
            return AstVisitStepResult::Stop;
        }
    }
    else
    {
        // Default enum type is 's32'
        typeView.typeRef = sema.typeMgr().getTypeInt(32, TypeInfo::Sign::Signed);
        typeView.type    = &sema.typeMgr().get(typeView.typeRef);
    }

    const IdentifierRef idRef = sema.idMgr().addIdentifier(ctx, srcViewRef(), tokNameRef);

    // Get the destination symbolMap
    SymbolFlags        flags     = SymbolFlagsE::Zero;
    SymbolMap*         symbolMap = sema.curSymMap();
    const SymbolAccess access    = sema.frame().currentAccess.value_or(sema.frame().defaultAccess);
    if (access == SymbolAccess::Internal)
        symbolMap = &sema.semaInfo().fileNamespace();
    else if (access == SymbolAccess::Public)
        flags.add(SymbolFlagsE::Public);

    // Creates symbol with type
    auto*          sym         = Symbol::make<SymbolEnum>(ctx, this, idRef, flags);
    const TypeInfo enumType    = TypeInfo::makeEnum(sym);
    const TypeRef  enumTypeRef = ctx.typeMgr().addType(enumType);
    sym->setTypeRef(enumTypeRef);
    sema.setSymbol(sema.curNodeRef(), sym);

    if (!symbolMap->addSingleSymbol(sema, sym))
        return AstVisitStepResult::Stop;

    sema.pushScope(SemaScopeFlagsE::Type);
    sema.curScope().setSymMap(sym);

    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstEnumDecl::semaPostNode(Sema& sema)
{
    sema.curSymMap()->setFullComplete(sema.ctx());
    sema.popScope();
    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
