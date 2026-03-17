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

    struct CloneContext final : swc::CloneContext
    {
        std::span<const ParamBinding> bindings;
        AstNodeRef                    replaceBreakRef    = AstNodeRef::invalid();
        AstNodeRef                    replaceContinueRef = AstNodeRef::invalid();

        explicit CloneContext(std::span<const ParamBinding> inBindings,
                              AstNodeRef                    inReplaceBreakRef    = AstNodeRef::invalid(),
                              AstNodeRef                    inReplaceContinueRef = AstNodeRef::invalid()) :
            bindings(inBindings),
            replaceBreakRef(inReplaceBreakRef),
            replaceContinueRef(inReplaceContinueRef)
        {
        }
    };

    AstNodeRef cloneAst(Sema& sema, AstNodeRef nodeRef, const CloneContext& cloneContext);
}

SWC_END_NAMESPACE();
