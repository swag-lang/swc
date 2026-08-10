#include "pch.h"
#include "Compiler/Sema/Helpers/SemaAccess.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.impl.h"
#include "Compiler/Sema/Symbol/Symbols.h"
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

    // The site that must satisfy the rule is where the code was WRITTEN, not where it ends up.
    // A token keeps its own source view through cloning, so an inlined body, a mixin and
    // '#inject'ed code all still answer with the file that declares them.
    const SourceFile* accessSiteFile(Sema& sema, const SourceViewRef siteViewRef)
    {
        if (const SourceFile* file = sema.compiler().sourceViewFile(siteViewRef))
            return file;
        return sema.file();
    }

    // Generated API files are copies of another module's source, so the module they stand for is
    // not the module being compiled. Comparing that one bit is enough: a generated file only ever
    // contains code that was already valid inside its own module.
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

        // Otherwise the answer comes from where the code was WRITTEN: the file that declares the
        // aggregate, or any file that declares an 'impl' of it. Going through the files instead of
        // the frame is what keeps an inlined body, a mixin and '#inject'ed code legal at every
        // expansion site, and what lets a type spread its 'impl' over platform or concern files.
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

    if (!inDeclaringModule(sema, field, siteViewRef))
        return false;

    return field.memberAccess() == MemberAccess::Internal || inDeclaringType(sema, *ownerStruct, siteViewRef);
}

Result SemaAccess::checkMemberAccess(Sema& sema, const Symbol& sym, const SourceCodeRef& codeRef)
{
    const auto* field = sym.safeCast<SymbolVariable>();
    if (!field || field->memberAccess() == MemberAccess::Public)
        return Result::Continue;

    const SymbolStruct* ownerStruct = ownerStructOf(sym);
    if (!ownerStruct)
        return Result::Continue;

    if (canAccessMember(sema, *field, codeRef.srcViewRef))
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

    // Const-ness of an lvalue reaches whatever it addresses, so marking a field that holds an
    // address would freeze the pointed-to value too. Assigning such a field is still rejected,
    // by the check that reports it by name.
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
