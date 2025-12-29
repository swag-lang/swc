#pragma once
#include "Parser/AstNode.h"

SWC_BEGIN_NAMESPACE()

class SymbolAttribute;

struct AttributeInstance
{
    const SymbolAttribute* symbol = nullptr;
};

struct ComputedAttributes
{
    SmallVector<AttributeInstance, 4> attributes;
};

SWC_END_NAMESPACE()
