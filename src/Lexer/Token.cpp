#include "pch.h"

#include "Lexer/SourceFile.h"
#include "Lexer/Token.h"

SWC_BEGIN_NAMESPACE();

std::string_view Token::toString(const SourceFile* file) const
{
    return {reinterpret_cast<const char*>(file->content().data()) + start, reinterpret_cast<const char*>(file->content().data()) + start + len};
}

SWC_END_NAMESPACE();
