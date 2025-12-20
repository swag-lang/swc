#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisitResult.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaFrame.h"
#include "Sema/Helpers/SemaInfo.h"
#include "Sema/Helpers/SemaNodeView.h"
#include "Sema/Sema.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstEnumDecl::semaPreChild(Sema& sema, const AstNodeRef& childRef)
{
    if (childRef != nodeBodyRef)
        return AstVisitStepResult::Continue;

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

    const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), srcViewRef(), tokNameRef);

    // Get the destination symbolMap
    SymbolFlags        flags     = SymbolFlagsE::Zero;
    SymbolMap*         symbolMap = sema.curSymMap();
    const SymbolAccess access    = sema.frame().currentAccess.value_or(sema.frame().defaultAccess);
    if (access == SymbolAccess::Internal)
        symbolMap = &sema.semaInfo().fileNamespace();
    else if (access == SymbolAccess::Public)
        flags.add(SymbolFlagsE::Public);

    // Creates symbol with type
    auto*          sym         = sema.compiler().allocate<SymbolEnum>(sema.ctx(), idRef, TypeRef::invalid(), flags);
    const TypeInfo enumType    = TypeInfo::makeEnum(sym);
    const TypeRef  enumTypeRef = sema.ctx().typeMgr().addType(enumType);
    sym->setTypeRef(enumTypeRef);
    symbolMap->addSymbol(sema.ctx(), sym);
    sema.setSymbol(sema.curNodeRef(), sym);

    sema.pushScope(SemaScopeFlagsE::Type);
    sema.curScope().setSymMap(sym);

    SemaFrame newFrame  = sema.frame();
    newFrame.symbolEnum = sym;
    sema.pushFrame(newFrame);

    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstEnumDecl::semaPostNode(Sema& sema)
{
    sema.curSymMap()->setFullComplete(sema.ctx());
    sema.popFrame();
    sema.popScope();
    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
