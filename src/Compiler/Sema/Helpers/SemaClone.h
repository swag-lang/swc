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
    };

    struct CloneContext final : ::swc::CloneContext
    {
        std::span<const ParamBinding> bindings;

        explicit CloneContext(std::span<const ParamBinding> inBindings) :
            bindings(inBindings)
        {
        }
    };

    AstNodeRef cloneExpr(Sema& sema, AstNodeRef nodeRef, const CloneContext& cloneContext);
}

SWC_END_NAMESPACE();
