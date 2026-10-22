#pragma once
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/NodePayload.h"
#include "Compiler/Sema/Core/Sema.h"

SWC_BEGIN_NAMESPACE();

namespace SemaCallArgument
{
    // Caller locations need an execution context; other defaults are complete here.
    inline bool tryResolveDefaultConstant(ConstantRef& outCstRef, const ResolvedCallArgument& arg)
    {
        outCstRef = ConstantRef::invalid();
        switch (arg.defaultKind)
        {
            case CallArgumentDefaultKind::Constant:
                outCstRef = arg.defaultCstRef;
                return true;

            case CallArgumentDefaultKind::CallerLocation:
                return false;

            case CallArgumentDefaultKind::None:
                break;
        }
        return true;
    }

    inline bool isImplicitTrailingCodeBlockArg(Sema& sema, const AstNode& argNode)
    {
        if (!argNode.is(AstNodeId::CompilerCodeBlock))
            return false;

        const AstNodeRef bodyRef = argNode.cast<AstCompilerCodeBlock>().nodeBodyRef;
        if (bodyRef.isInvalid())
            return false;

        const AstNode& bodyNode = sema.node(bodyRef);
        if (!bodyNode.is(AstNodeId::EmbeddedBlock))
            return false;

        return bodyNode.cast<AstEmbeddedBlock>().hasFlag(AstEmbeddedBlockFlagsE::ImplicitCodeBlockArg);
    }

    inline bool isImplicitTrailingCodeBlockArg(Sema& sema, AstNodeRef argRef)
    {
        return isImplicitTrailingCodeBlockArg(sema, sema.node(argRef));
    }
}

SWC_END_NAMESPACE();
