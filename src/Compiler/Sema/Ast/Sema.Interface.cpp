#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaDeclGhost.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE();

Result AstInterfaceDecl::semaPreDecl(Sema& sema) const
{
    SemaHelpers::registerSymbol<SymbolInterface>(sema, *this, tokNameRef);
    return Result::SkipChildren;
}

Result AstInterfaceDecl::semaPreNode(Sema& sema) const
{
    return SemaDeclGhost::run(sema, *this);
}

Result AstInterfaceDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::Continue;

    TaskContext& ctx = sema.ctx();

    // A rejected base leaves the interface without one, so its users still find it complete.
    auto& symItf = sema.curViewSymbol().sym()->cast<SymbolInterface>();
    if (nodeBaseRef.isValid())
    {
        const TypeRef baseTypeRef = ctx.typeMgr().unwrapNonStrictAlias(sema.viewType(nodeBaseRef).typeRef());
        if (baseTypeRef.isValid() && ctx.typeMgr().get(baseTypeRef).isStruct())
        {
            symItf.setBaseTypeRef(baseTypeRef);
        }
        else
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_interface_base_not_struct, nodeBaseRef);
            diag.addArgument(Diagnostic::ARG_SYM, symItf.name(ctx));
            diag.addArgument(Diagnostic::ARG_TYPE, baseTypeRef);
            diag.report(ctx);
        }
    }

    const TypeInfo itfType    = TypeInfo::makeInterface(&symItf);
    const TypeRef  itfTypeRef = ctx.typeMgr().addType(itfType);

    symItf.setTypeRef(itfTypeRef);
    symItf.setTyped(sema.ctx());

    SemaFrame frame = sema.frame();
    frame.setCurrentInterface(&symItf);
    sema.pushFramePopOnPostNode(std::move(frame));

    sema.pushScopePopOnPostNode(SemaScopeFlagsE::Type | SemaScopeFlagsE::Interface);
    sema.curScope().setSymMap(&symItf);

    return Result::Continue;
}

Result AstInterfaceDecl::semaPostNode(Sema& sema)
{
    auto& sym = sema.curViewSymbol().sym()->cast<SymbolInterface>();
    SWC_RESULT(sym.canBeCompleted(sema));
    sym.setSemaCompleted(sema.ctx());

    return Result::Continue;
}

SWC_END_NAMESPACE();
