#pragma once
#include "Compiler/Parser/Ast/AstNode.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class Ast;
class SymbolVariable;

namespace SemaClone
{
    struct ParamBinding
    {
        IdentifierRef         idRef;
        AstNodeRef            exprRef;
        TypeRef               typeRef          = TypeRef::invalid();
        ConstantRef           cstRef           = ConstantRef::invalid();
        bool                  forceMaterialize = false;
        const SymbolVariable* sourceParam      = nullptr;
    };

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
        const Ast*                       sourceAst                = nullptr;
        bool                             preserveFunctionGenerics = false;
        bool                             preserveBindingExprState = false;
        bool                             duplicateRuntimeStorage  = false;
        uint32_t                         breakableDepth           = 0;
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
    AstNodeRef cloneDetachedExpr(Sema& sema, AstNodeRef nodeRef);
}

SWC_END_NAMESPACE();
