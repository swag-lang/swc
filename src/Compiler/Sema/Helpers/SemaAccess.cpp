#include "pch.h"
#include "Compiler/Sema/Helpers/SemaAccess.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
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
