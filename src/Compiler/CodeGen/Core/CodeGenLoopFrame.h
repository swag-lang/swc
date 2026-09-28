#pragma once
#include "Compiler/CodeGen/Core/CodeGen.h"

SWC_BEGIN_NAMESPACE();

namespace CodeGenLoopFrame
{
    inline void push(CodeGen& codeGen, CodeGenFrame& frame, MicroLabelRef continueLabel, MicroLabelRef doneLabel)
    {
        frame.setCurrentBreakContent(codeGen.curNodeRef(), CodeGenFrame::BreakContextKind::Loop);
        frame.setCurrentLoopContinueLabel(continueLabel);
        frame.setCurrentLoopBreakLabel(doneLabel);
        codeGen.pushFrame(frame);
    }

    inline void pushWithDeferScope(CodeGen& codeGen, CodeGenFrame& frame, MicroLabelRef continueLabel, MicroLabelRef doneLabel)
    {
        push(codeGen, frame, continueLabel, doneLabel);
        codeGen.pushDeferScope(AstNodeRef::invalid(), codeGen.curNodeRef());
    }
}

SWC_END_NAMESPACE();
