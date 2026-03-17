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

        explicit CloneContext(std::span<const ParamBinding>    inBindings,
                              std::span<const NodeReplacement> inReplacements = std::span<const NodeReplacement>{}) :
            bindings(inBindings),
            replacements(inReplacements)
        {
        }
    };

    AstNodeRef cloneAst(Sema& sema, AstNodeRef nodeRef, const CloneContext& cloneContext);
}

SWC_END_NAMESPACE();
