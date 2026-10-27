#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Main/CompilerInstance.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    // 'interface I is Base' reads an 'I' value as a pointer to 'Base', so each implementation
    // has to start with it, embedded by value with 'using'.
    Result checkInterfaceBase(Sema& sema, const SymbolImpl& symImpl)
    {
        const SymbolInterface* symInterface = symImpl.symInterface();
        const SymbolStruct*    symStruct    = symImpl.symStruct();
        if (!symInterface || !symStruct)
            return Result::Continue;

        // The base is recorded before the interface type exists, and this impl names that type.
        const TypeRef baseTypeRef = symInterface->baseTypeRef();
        if (!baseTypeRef.isValid())
            return Result::Continue;

        SWC_RESULT(sema.waitSemaCompleted(symStruct, symImpl.codeRef()));

        const SymbolStruct&                    baseStruct = sema.typeMgr().get(baseTypeRef).payloadSymStruct();
        SmallVector<SymbolStructUsingPathStep> usingPath;
        bool                                   startsWithBase = symStruct->resolveUsingFieldPath(sema.ctx(), baseStruct, usingPath);
        for (const SymbolStructUsingPathStep& step : usingPath)
            startsWithBase = startsWithBase && !step.isPointer && step.field->offset() == 0;
        if (startsWithBase)
            return Result::Continue;

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_interface_base_not_embedded, symImpl);
        diag.addArgument(Diagnostic::ARG_SYM, symInterface->name(sema.ctx()));
        diag.addArgument(Diagnostic::ARG_TYPE, symStruct->typeRef());
        diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, baseTypeRef);
        diag.report(sema.ctx());
        return Result::Error;
    }

    IdentifierRef resolveImplRegistrationTargetId(Sema& sema, AstNodeRef nodeRef)
    {
        const SemaNodeView targetView{sema, nodeRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Symbol};
        if (targetView.hasSymbol())
            return targetView.sym()->idRef();

        return sema.idMgr().addIdentifier(sema.ctx(), targetView.node()->codeRef());
    }

    void registerPendingImplTarget(Sema& sema, SymbolImpl& symImpl, AstNodeRef nodeRef)
    {
        if (symImpl.pendingRegistrationTargetIdRef().isValid())
            return;

        const IdentifierRef targetIdRef = resolveImplRegistrationTargetId(sema, nodeRef);
        SWC_ASSERT(targetIdRef.isValid());

        symImpl.setPendingRegistrationTargetIdRef(targetIdRef);
        sema.compiler().incPendingImplRegistrations(targetIdRef);
    }
}

Result AstImpl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeIdentRef || childRef == nodeForRef)
        return Result::Continue;

    const SymbolImpl* symImpl = sema.frame().currentImpl();
    if (!symImpl || !symImpl->isForStruct())
        return Result::Continue;

    const SymbolStruct* symStruct = symImpl->symStruct();
    if (!symStruct || !symStruct->isGenericRoot())
        return Result::Continue;

    return Result::SkipChildren;
}

Result AstImpl::semaPostDeclChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeIdentRef)
    {
        const SemaNodeView identView{sema, nodeIdentRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Symbol};
        IdentifierRef      idRef = IdentifierRef::invalid();
        if (identView.hasSymbol())
            idRef = identView.sym()->idRef();
        else
            idRef = sema.idMgr().addIdentifier(sema.ctx(), identView.node()->codeRef());

        auto* sym = Symbol::make<SymbolImpl>(sema.ctx(), this, tokRef(), idRef, SymbolFlagsE::Zero);
        sema.setSymbol(sema.curNodeRef(), sym);

        if (identView.hasSymbol())
        {
            Symbol* target = identView.sym();
            if (target->isStruct())
                sym->setSymStruct(&target->cast<SymbolStruct>());
            else if (target->isEnum())
                sym->setSymEnum(&target->cast<SymbolEnum>());
            else if (target->isInterface())
                sym->setSymInterface(&target->cast<SymbolInterface>());
        }

        // Target lookup finishes in the second pass. Count pending registrations
        // by target so unrelated impls cannot block each other's structs.
        if (nodeForRef.isInvalid())
            registerPendingImplTarget(sema, *sym, nodeIdentRef);

        sema.pushScopePopOnPostNode(SemaScopeFlagsE::TopLevel | SemaScopeFlagsE::Impl);
        sema.curScope().setSymMap(sym);
    }
    else if (childRef == nodeForRef)
    {
        auto& symImpl = sema.curViewSymbol().sym()->cast<SymbolImpl>();
        registerPendingImplTarget(sema, symImpl, nodeForRef);
    }

    return Result::Continue;
}

Result AstImpl::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    auto& symImpl = sema.curViewSymbol().sym()->cast<SymbolImpl>();

    if (childRef == nodeIdentRef)
    {
        const SemaNodeView identView = sema.viewSymbol(nodeIdentRef);
        Symbol&            sym       = *(identView.sym());
        symImpl.setIdRef(sym.idRef());
        if (nodeForRef.isInvalid())
        {
            if (sym.isStruct())
                sym.cast<SymbolStruct>().addImpl(sema, symImpl);
            else if (sym.isEnum())
                sym.cast<SymbolEnum>().addImpl(sema, symImpl);
            else
                return SemaError::raise(sema, DiagnosticId::sema_err_impl_not_struct, nodeIdentRef);
        }
        else
        {
            // Sibling impl blocks share the interface's name, so parallel lookup may
            // return an impl instead. Its symInterface was initialized before
            // registration; use it to recover and bind the interface symbol.
            SymbolInterface* symInterface = nullptr;
            if (sym.isInterface())
            {
                symInterface = &sym.cast<SymbolInterface>();
            }
            else
            {
                symInterface = sym.isImpl() ? sym.cast<SymbolImpl>().symInterface() : nullptr;
                if (!symInterface)
                    return SemaError::raise(sema, DiagnosticId::sema_err_impl_not_interface, nodeIdentRef);

                sema.setSymbol(nodeIdentRef, symInterface);
            }

            symImpl.setSymInterface(symInterface);
        }

        if (nodeForRef.isValid())
            return Result::Continue;
    }

    if (childRef == nodeForRef)
    {
        const SemaNodeView identView = sema.viewType(nodeIdentRef);
        const SemaNodeView forView   = sema.viewSymbol(nodeForRef);
        if (!forView.sym()->isStruct())
            return SemaError::raise(sema, DiagnosticId::sema_err_impl_not_struct, nodeForRef);

        SWC_RESULT(forView.sym()->cast<SymbolStruct>().addInterface(sema, symImpl));

        symImpl.addExtraFlag(SymbolImplFlagsE::ForInterface);
        symImpl.setTypeRef(identView.typeRef());
        symImpl.setDeclared(sema.ctx());
        symImpl.setTyped(sema.ctx());
    }

    if ((childRef == nodeIdentRef && nodeForRef.isInvalid()) || childRef == nodeForRef)
    {
        // Complete registration only after the resolved impl is attached.
        if (!symImpl.isPendingRegistrationResolved())
        {
            symImpl.setPendingRegistrationResolved();
            sema.compiler().decPendingImplRegistrations(symImpl.pendingRegistrationTargetIdRef());
        }

        auto frame = sema.frame();
        frame.setCurrentImpl(&symImpl);
        sema.pushFramePopOnPostNode(std::move(frame));
        sema.pushScopePopOnPostNode(SemaScopeFlagsE::TopLevel | SemaScopeFlagsE::Impl);
        sema.curScope().setSymMap(symImpl.asSymMap());
    }

    return Result::Continue;
}

Result AstImpl::semaPostNode(Sema& sema)
{
    auto&        symImpl = sema.curViewSymbol().sym()->cast<SymbolImpl>();
    const Result result  = symImpl.isForInterface() ? checkInterfaceBase(sema, symImpl) : Result::Continue;
    if (result == Result::Pause)
        return result;

    // A rejected base still completes the impl, so nothing waiting on it is left behind.
    symImpl.setDeclared(sema.ctx());
    symImpl.setTyped(sema.ctx());
    symImpl.setSemaCompleted(sema.ctx());

    return result;
}

void AstImpl::semaErrorCleanup(Sema& sema, AstNodeRef nodeRef)
{
    const SemaNodeView view = sema.viewSymbol(nodeRef);
    if (!view.hasSymbol())
        return;

    auto& symImpl = view.sym()->cast<SymbolImpl>();
    if (!symImpl.isPendingRegistrationResolved())
    {
        symImpl.setPendingRegistrationResolved();
        sema.compiler().decPendingImplRegistrations(symImpl.pendingRegistrationTargetIdRef());
    }
}

SWC_END_NAMESPACE();
