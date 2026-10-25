#pragma once
#include "Compiler/Parser/Ast/AstNode.h"
#include "Compiler/Sema/Helpers/SemaCloneTypes.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class Ast;

namespace SemaClone
{
    struct NodeReplacement
    {
        AstNodeId  nodeId                = AstNodeId::Invalid;
        AstNodeRef replacementRef        = AstNodeRef::invalid();
        bool       topLevelBreakableOnly = false;
    };

    struct CloneContext final : swc::CloneContext
    {
        std::span<const ParamBinding>    bindings;
        std::span<const NodeReplacement> replacements;

        const Ast* sourceAst = nullptr;

        bool preserveFunctionGenerics             = false;
        bool preserveBindingExprState             = false;
        bool duplicateRuntimeStorage              = false;
        bool resolveBindingExprWithParentBindings = false;

        // Preserve resolved symbols on same-AST clones, as cross-AST cloning already does.
        // Callee helpers/globals/constants keep their original symbols when inlined;
        // preserveSyntheticSymbol excludes locals/parameters so they can be rebound.
        bool     preserveResolvedSymbols = false;
        uint32_t breakableDepth          = 0;

        // Nested callables have independent frames and cannot read expressions
        // bound to names in the caller's expansion frame.
        uint32_t nestedCallableDepth = 0;

        AstNodeRef suppressedImplicitCastSubstituteRef = AstNodeRef::invalid();

        explicit CloneContext(std::span<const ParamBinding> inBindings, std::span<const NodeReplacement> inReplacements = std::span<const NodeReplacement>{}, bool inPreserveFunctionGenerics = false, const Ast* inSourceAst = nullptr, bool inPreserveBindingExprState = false, bool inDuplicateRuntimeStorage = false, uint32_t inBreakableDepth = 0) :
            bindings(inBindings),
            replacements(inReplacements),
            sourceAst(inSourceAst),
            preserveFunctionGenerics(inPreserveFunctionGenerics),
            preserveBindingExprState(inPreserveBindingExprState),
            duplicateRuntimeStorage(inDuplicateRuntimeStorage),
            breakableDepth(inBreakableDepth)
        {
        }
    };

    AstNodeRef cloneAst(Sema& sema, AstNodeRef nodeRef, const CloneContext& cloneContext);
    AstNodeRef cloneAstPreservingResolvedIdentifierSymbols(Sema& sema, AstNodeRef nodeRef, const CloneContext& cloneContext);
    AstNodeRef cloneDetachedExpr(Sema& sema, AstNodeRef nodeRef, bool* needsReanalysis = nullptr);
}

SWC_END_NAMESPACE();
