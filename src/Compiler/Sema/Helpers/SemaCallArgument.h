#pragma once
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"

SWC_BEGIN_NAMESPACE();

namespace SemaCallArgument
{
    inline bool isImplicitTrailingCodeBlockArg(Sema& sema, AstNodeRef argRef)
    {
        const AstNode& argNode = sema.node(argRef);
        if (!argNode.is(AstNodeId::CompilerCodeBlock))
            return false;

        const AstNodeRef bodyRef = argNode.cast<AstCompilerCodeBlock>().nodeBodyRef;
        if (bodyRef.isInvalid())
            return false;
        if (!sema.node(bodyRef).is(AstNodeId::EmbeddedBlock))
            return false;

        return sema.node(bodyRef).cast<AstEmbeddedBlock>().hasFlag(AstEmbeddedBlockFlagsE::ImplicitCodeBlockArg);
    }
}

SWC_END_NAMESPACE();
