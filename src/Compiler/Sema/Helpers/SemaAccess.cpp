#include "pch.h"
#include "Compiler/Sema/Helpers/SemaAccess.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.impl.h"
#include "Compiler/SourceFile.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    const SymbolStruct* ownerStructOf(const Symbol& sym)
    {
        const SymbolMap* owner = sym.ownerSymMap();
        return owner ? owner->safeCast<SymbolStruct>() : nullptr;
    }

    // Check where code was written. Tokens retain that source view through
    // inlining, mixin expansion, and #inject.
    const SourceFile* accessSiteFile(Sema& sema, const SourceViewRef siteViewRef)
    {
        if (const SourceFile* file = sema.compiler().sourceViewFile(siteViewRef))
            return file;

        return sema.file();
    }

    // Generated API files represent imported modules, not the current module.
    // Their source was already valid in its own module, so the imported/local
    // distinction is enough here.
    bool inDeclaringModule(Sema& sema, const Symbol& sym, const SourceViewRef siteViewRef)
    {
        const SourceFile* declFile = sema.compiler().sourceViewFile(sym);
        const SourceFile* siteFile = accessSiteFile(sema, siteViewRef);
        if (!declFile || !siteFile)
            return true;

        return declFile->isImportedApi() == siteFile->isImportedApi();
    }

    bool inDeclaringType(Sema& sema, const SymbolStruct& ownerStruct, const SourceViewRef siteViewRef)
    {
        const SymbolStruct& ownerRoot = *ownerStruct.genericRootOrSelf();

        if (const SymbolImpl* impl = sema.frame().currentImpl())
        {
            // A generic instance and its root share one declaration, hence one access contract.
            const SymbolStruct* implStruct = impl->symStruct();
            if (implStruct && implStruct->genericRootOrSelf() == &ownerRoot)
                return true;
        }

        // Use the original source file for expanded code. The aggregate's file
        // and every impl file retain access, allowing implementations to be
        // split across platform or concern files.
        const SourceFile* siteFile = accessSiteFile(sema, siteViewRef);
        if (!siteFile)
            return false;

        if (sema.compiler().sourceViewFile(ownerRoot) == siteFile)
            return true;

        for (const SymbolImpl* impl : ownerRoot.impls())
        {
            if (sema.compiler().sourceViewFile(*impl) == siteFile)
                return true;
        }

        return false;
    }

    // A method takes its access from its 'impl', or from its own modifier, and 'private' grants
    // the declaring type exactly as it does on a field. A method that implements an interface
    // answers to the interface instead, which every holder of the interface may call.
    const SymbolStruct* privateMethodOwner(const Symbol& sym)
    {
        const auto* function = sym.safeCast<SymbolFunction>();
        if (!function || !function->isPrivate())
            return nullptr;

        const SymbolMap* owner = function->ownerSymMap();
        const auto*      impl  = owner ? owner->safeCast<SymbolImpl>() : nullptr;
        if (!impl || impl->isForInterface())
            return nullptr;

        return impl->symStruct();
    }

    bool canCallPrivateMethod(Sema& sema, const SymbolFunction& method, const SymbolStruct& ownerStruct, const SourceViewRef siteViewRef)
    {
        return inDeclaringModule(sema, method, siteViewRef) && inDeclaringType(sema, ownerStruct, siteViewRef);
    }

    __forceinline bool canAccessMemberInOwner(Sema& sema, const SymbolVariable& field, const SymbolStruct& ownerStruct, const SourceViewRef siteViewRef)
    {
        if (!inDeclaringModule(sema, field, siteViewRef))
            return false;

        return field.memberAccess() == MemberAccess::Internal || inDeclaringType(sema, ownerStruct, siteViewRef);
    }

    template<typename AT>
    Diagnostic buildMemberDiagnostic(Sema& sema, DiagnosticId id, const SymbolVariable& field, const SymbolStruct& ownerStruct, const AT& at)
    {
        Diagnostic diag = SemaError::report(sema, id, at);
        diag.addArgument(Diagnostic::ARG_SYM, field.name(sema.ctx()));
        diag.addArgument(Diagnostic::ARG_TYPE, ownerStruct.getFullScopedName(sema.ctx()));

        diag.addNote(DiagnosticId::sema_note_field_access_declared_here);
        diag.last().addArgument(Diagnostic::ARG_SYM, field.name(sema.ctx()));
        diag.last().addSpan(field.codeRange(sema.ctx()));

        return diag;
    }
}

bool SemaAccess::canAccessMember(Sema& sema, const SymbolVariable& field, const SourceViewRef siteViewRef)
{
    if (field.memberAccess() == MemberAccess::Public)
        return true;

    const SymbolStruct* ownerStruct = ownerStructOf(field);
    if (!ownerStruct)
        return true;

    return canAccessMemberInOwner(sema, field, *ownerStruct, siteViewRef);
}

bool SemaAccess::canAccessSymbol(Sema& sema, const Symbol& sym, const SourceViewRef siteViewRef)
{
    if (const auto* field = sym.safeCast<SymbolVariable>())
        return canAccessMember(sema, *field, siteViewRef);

    const SymbolStruct* ownerStruct = privateMethodOwner(sym);
    return !ownerStruct || canCallPrivateMethod(sema, sym.cast<SymbolFunction>(), *ownerStruct, siteViewRef);
}

void SemaAccess::dropUnreachableOverloads(Sema& sema, SmallVector<const Symbol*>& symbols, const SourceViewRef siteViewRef)
{
    // Leave a set with nothing reachable intact, so the access check can name what is private.
    if (symbols.size() < 2)
        return;

    const auto reachable = [&](const Symbol* sym) {
        return canAccessSymbol(sema, *sym, siteViewRef);
    };
    if (std::ranges::all_of(symbols, reachable) || std::ranges::none_of(symbols, reachable))
        return;

    size_t kept = 0;
    for (const Symbol* sym : symbols)
    {
        if (reachable(sym))
            symbols[kept++] = sym;
    }

    symbols.resize(kept);
}

Result SemaAccess::checkMemberAccess(Sema& sema, const Symbol& sym, const SourceCodeRef& codeRef)
{
    if (const SymbolStruct* methodOwner = privateMethodOwner(sym))
    {
        const auto& method = sym.cast<SymbolFunction>();
        if (canCallPrivateMethod(sema, method, *methodOwner, codeRef.srcViewRef))
            return Result::Continue;

        Diagnostic diag = SemaError::report(sema, DiagnosticId::sema_err_method_private, codeRef);
        diag.addArgument(Diagnostic::ARG_SYM, method.name(sema.ctx()));
        diag.addArgument(Diagnostic::ARG_TYPE, methodOwner->getFullScopedName(sema.ctx()));
        diag.addNote(DiagnosticId::sema_note_method_access_declared_here);
        diag.last().addArgument(Diagnostic::ARG_SYM, method.name(sema.ctx()));
        diag.last().addSpan(method.codeRange(sema.ctx()));
        diag.report(sema.ctx());
        return Result::Error;
    }

    const auto* field = sym.safeCast<SymbolVariable>();
    if (!field || field->memberAccess() == MemberAccess::Public)
        return Result::Continue;

    const SymbolStruct* ownerStruct = ownerStructOf(sym);
    if (!ownerStruct)
        return Result::Continue;

    if (canAccessMemberInOwner(sema, *field, *ownerStruct, codeRef.srcViewRef))
        return Result::Continue;

    const DiagnosticId id = field->memberAccess() == MemberAccess::Internal ? DiagnosticId::sema_err_field_internal : DiagnosticId::sema_err_field_private;
    buildMemberDiagnostic(sema, id, *field, *ownerStruct, codeRef).report(sema.ctx());

    return Result::Error;
}

bool SemaAccess::canWriteMember(Sema& sema, const SymbolVariable& field, const SourceViewRef siteViewRef)
{
    if (!field.isMemberReadOnly())
        return true;

    const SymbolStruct* ownerStruct = ownerStructOf(field);
    if (!ownerStruct)
        return true;

    return inDeclaringModule(sema, field, siteViewRef) && inDeclaringType(sema, *ownerStruct, siteViewRef);
}

void SemaAccess::markUnwritableMemberAccess(Sema& sema, const SymbolVariable& field, const AstNodeRef accessRef, const SourceViewRef siteViewRef)
{
    if (canWriteMember(sema, field, siteViewRef))
        return;

    // Const on an address-holding lvalue would freeze its pointee too. Reject
    // writes to the field separately, preserving access to the pointed-to value.
    if (field.typeRef().isValid())
    {
        const TypeRef unwrappedRef = SemaHelpers::unwrapAliasRefType(sema.ctx(), field.typeRef());
        if (unwrappedRef.isValid() && sema.typeMgr().get(unwrappedRef).isPointerOrReference())
            return;
    }

    sema.setConstAssignTarget(accessRef);
}

Result SemaAccess::reportMemberWrite(Sema& sema, const SymbolVariable& field, AstNodeRef nodeRef)
{
    const SymbolStruct* ownerStruct = ownerStructOf(field);
    SWC_ASSERT(ownerStruct);

    buildMemberDiagnostic(sema, DiagnosticId::sema_err_field_readonly, field, *ownerStruct, nodeRef).report(sema.ctx());

    return Result::Error;
}

SWC_END_NAMESPACE();
