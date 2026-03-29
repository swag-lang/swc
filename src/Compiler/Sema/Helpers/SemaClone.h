#pragma once
#include "Compiler/Parser/Ast/AstNode.h"

SWC_BEGIN_NAMESPACE();

class Sema;

namespace SemaClone
{
    struct ParamBinding
    {
        IdentifierRef idRef;
        AstNodeRef    exprRef;
        TypeRef       typeRef = TypeRef::invalid();
        ConstantRef   cstRef  = ConstantRef::invalid();
    };

    struct NodeReplacement
    {
        AstNodeId  nodeId         = AstNodeId::Invalid;
        AstNodeRef replacementRef = AstNodeRef::invalid();
    };

    struct CloneContext final : swc::CloneContext
    {
        std::span<const ParamBinding>    bindings;
        std::span<const NodeReplacement> replacements;
        bool                             preserveFunctionGenerics = false;

        explicit CloneContext(std::span<const ParamBinding>    inBindings,
                              std::span<const NodeReplacement> inReplacements = std::span<const NodeReplacement>{},
                              bool                             inPreserveFunctionGenerics = false) :
            bindings(inBindings),
            replacements(inReplacements),
            preserveFunctionGenerics(inPreserveFunctionGenerics)
        {
        }
    };

    AstNodeRef cloneAst(Sema& sema, AstNodeRef nodeRef, const CloneContext& cloneContext);
}

SWC_END_NAMESPACE();
