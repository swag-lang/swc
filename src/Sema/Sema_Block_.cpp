#include "pch.h"

#include "Helpers/SemaError.h"
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

AstVisitStepResult AstScopeResolution::semaPostNode(Sema& sema)
{
    const SemaNodeView nodeView(sema, nodeLeftRef);
    SWC_ASSERT(nodeView.sym && nodeView.sym->is(SymbolKind::Enum));
    if (!nodeView.sym->isFullComplete())
        return sema.pause(TaskStateKind::SemaWaitingFullComplete, nodeLeftRef);

    const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), srcViewRef(), tokMemberRef);

    if (nodeView.sym->is(SymbolKind::Enum))
    {
        const auto& symMap = nodeView.sym->cast<SymbolEnum>();
        SmallVector<Symbol*> matches;
        symMap.lookup(idRef, matches);
        SWC_ASSERT(matches.size() == 1);
        const auto& symValue = matches[0]->cast<SymbolEnumValue>();
        sema.semaInfo().setConstant(sema.curNodeRef(), symValue.cstRef());
    }
    else
    {
        SemaError::raiseInternal(sema, *this);
    }

    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
