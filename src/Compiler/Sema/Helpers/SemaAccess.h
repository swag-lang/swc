#pragma once
#include "Compiler/Parser/Ast/AstNode.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class Symbol;
class SymbolVariable;
struct SourceCodeRef;

// Members default to internal (module access). Private access covers the type's
// declaration file and impl files in that module. Readonly preserves read access
// while restricting writes to the declaring type.
namespace SemaAccess
{
    Result checkMemberAccess(Sema& sema, const Symbol& sym, const SourceCodeRef& codeRef);

    // Silent checks let callers provide their own diagnostic context.
    bool canAccessMember(Sema& sema, const SymbolVariable& field, SourceViewRef siteViewRef);
    bool canWriteMember(Sema& sema, const SymbolVariable& field, SourceViewRef siteViewRef);

    Result reportMemberWrite(Sema& sema, const SymbolVariable& field, AstNodeRef nodeRef);

    // Mark unwritable value members so assignments, mutable addresses, and
    // mutable reference arguments fail. Address-holding fields are checked
    // separately to avoid freezing their pointees.
    void markUnwritableMemberAccess(Sema& sema, const SymbolVariable& field, AstNodeRef accessRef, SourceViewRef siteViewRef);
}

SWC_END_NAMESPACE();
