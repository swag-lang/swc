#pragma once
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"

SWC_BEGIN_NAMESPACE();

namespace SemaCallArgument
{
    inline bool isImplicitTrailingCodeBlockArg(Sema& sema, const AstNode& argNode)
    {
        if (!argNode.is(AstNodeId::CompilerCodeBlock))
            return false;

        const AstNodeRef bodyRef = argNode.cast<AstCompilerCodeBlock>().nodeBodyRef;
        if (bodyRef.isInvalid())
            return false;
        if (!sema.node(bodyRef).is(AstNodeId::EmbeddedBlock))
            return false;

        return sema.node(bodyRef).cast<AstEmbeddedBlock>().hasFlag(AstEmbeddedBlockFlagsE::ImplicitCodeBlockArg);
    }

    inline bool isImplicitTrailingCodeBlockArg(Sema& sema, AstNodeRef argRef)
    {
        return isImplicitTrailingCodeBlockArg(sema, sema.node(argRef));
    }
}

SWC_END_NAMESPACE();
