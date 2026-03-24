#pragma once
#include "Compiler/Parser/Ast/AstNode.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

struct SemaDeferPayload
{
    AstNodeRef              bodyRef = AstNodeRef::invalid();
    SmallVector<AstNodeRef> parentPath;
};

SWC_END_NAMESPACE();
