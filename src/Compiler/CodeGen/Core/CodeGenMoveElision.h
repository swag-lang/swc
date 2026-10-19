#pragma once
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class CodeGen;
class SymbolVariable;

// Elide both reset and scope-exit drop for provably dead plain locals moved from
// by assignment or initialization. A conservative lexical proof rejects escaped
// addresses, later uses, and moves that do not post-dominate later scope exits.
namespace CodeGenMoveElision
{
    // Resolve a directly named struct local, including initializer wrappers. Its
    // frame slot must hold the struct itself; optionally return the identifier ref.
    const SymbolVariable* directStructVariable(CodeGen& codeGen, AstNodeRef nodeRef, AstNodeRef* outResolvedRef = nullptr);

    // True when 'symVar' is provably dead after the move whose resolved source node is
    // 'resolvedSourceRef': the reset and the scope-exit drop can be elided.
    bool canElideMoveSource(CodeGen& codeGen, const SymbolVariable& symVar, AstNodeRef resolvedSourceRef);

    // A return can transfer ownership unless a defer or closure can still observe
    // the local. Lexically later uses belong to other control paths, so the
    // last-use and post-domination rules of canElideMoveSource do not apply.
    bool canMoveOutAtReturn(CodeGen& codeGen, const SymbolVariable& symVar);
}

SWC_END_NAMESPACE();
