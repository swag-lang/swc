#include "pch.h"
#include "Helpers/SemaNodeView.h"
#include "Main/CompilerInstance.h"
#include "Sema/Sema.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstFile::semaPreNode(Sema& sema) const
{
    SymbolNamespace* fileNamespace = Symbol::make<SymbolNamespace>(sema.ctx(), this, IdentifierRef::invalid(), SymbolFlagsE::Zero);
    sema.semaInfo().setFileNamespace(*fileNamespace);
    sema.pushScope(SemaScopeFlagsE::TopLevel);
    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstFile::semaPostNode(Sema& sema)
{
    sema.popScope();
    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstScopeResolution::semaPreChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeLeftRef)
        return AstVisitStepResult::Continue;

    const SemaNodeView nodeView(sema, nodeLeftRef);
    SWC_ASSERT(nodeView.sym && nodeView.sym->is(SymbolKind::Enum));

    sema.pushScope(SemaScopeFlagsE::Type);
    sema.curScope().setSymMap(static_cast<SymbolMap*>(nodeView.sym));

    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstScopeResolution::semaPostNode(Sema& sema)
{
    sema.popScope();
    sema.semaInherit(*this, nodeRightRef);
    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
