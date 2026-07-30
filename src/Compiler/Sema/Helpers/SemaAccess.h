#pragma once
#include "Compiler/Parser/Ast/AstNode.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class Symbol;
class SymbolVariable;
struct SourceCodeRef;

// Access control for aggregate members. A member belongs to its type, so 'private' grants the
// file that declares the aggregate plus every 'impl' of that type in the declaring module;
// 'internal' grants the whole declaring module; 'readonly' grants reads to everyone and writes
// to the declaring type only.
namespace SemaAccess
{
    // Rejects a member the current site cannot name at all ('private', 'internal').
    Result checkMemberAccess(Sema& sema, const Symbol& sym, const SourceCodeRef& codeRef);

    // The silent form of 'checkMemberAccess', for paths that report through their own machinery.
    bool canAccessMember(Sema& sema, const SymbolVariable& field, SourceViewRef siteViewRef);

    // True when the site can write 'field'. A 'readonly' field reads everywhere but writes only
    // from its own type.
    bool canWriteMember(Sema& sema, const SymbolVariable& field, SourceViewRef siteViewRef);

    // Reports the write rejected by 'canWriteMember'.
    Result reportMemberWrite(Sema& sema, const SymbolVariable& field, AstNodeRef nodeRef);

    // Marks a member access the site cannot write, so the const paths reject an assignment, a
    // mutable address and a mutable by-reference argument. 'readonly' restricts writing the
    // field itself, so a field that points somewhere else does not freeze what it points to.
    void markUnwritableMemberAccess(Sema& sema, const SymbolVariable& field, AstNodeRef accessRef, SourceViewRef siteViewRef);
}

SWC_END_NAMESPACE();
