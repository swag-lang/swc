#pragma once
#include "Support/Core/RefTypes.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class SymbolFunction;

namespace SemaJIT::ScalarCache
{
    Utf8 buildKey(Sema& sema, const SymbolFunction& evaluator, AstNodeRef expression, TypeRef resultType);
    bool read(std::span<std::byte> value, const Utf8& key);
    void write(const Utf8& key, std::span<const std::byte> value);
}

SWC_END_NAMESPACE();
