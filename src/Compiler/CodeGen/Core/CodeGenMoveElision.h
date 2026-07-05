#pragma once
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class CodeGen;
class SymbolVariable;

// Drop elision for moved-from sources ('a = #move b', 'var a = #move b'): when 'b' is a
// plain local that is provably never used again, the compiler skips both the
// reset-to-default of 'b' and its scope-exit 'opDrop' ('opDrop' is then not called on
// the reset value). The proof is a conservative lexical analysis of the function body:
// any use that could leak the local's address, any use after the move, or a move that
// does not post-dominate the later exits of the declaring scope, forbids the elision.
namespace CodeGenMoveElision
{
    // The variable a node directly names (descending an initializer wrapper), when its
    // frame slot holds the struct itself (not a reference/pointer to it). Fills
    // 'outResolvedRef' with the resolved identifier node when provided.
    const SymbolVariable* directStructVariable(CodeGen& codeGen, AstNodeRef nodeRef, AstNodeRef* outResolvedRef = nullptr);

    // True when 'symVar' is provably dead after the move whose resolved source node is
    // 'resolvedSourceRef': the reset and the scope-exit drop can be elided.
    bool canElideMoveSource(CodeGen& codeGen, const SymbolVariable& symVar, AstNodeRef resolvedSourceRef);
}

SWC_END_NAMESPACE();
