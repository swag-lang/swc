#include "pch.h"
#include "Parser/AstNodes.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef AstCompilerIf::semaPreChild(SemaJob& job, AstNodeRef childRef)
{
    return childRef;
}

SWC_END_NAMESPACE()
