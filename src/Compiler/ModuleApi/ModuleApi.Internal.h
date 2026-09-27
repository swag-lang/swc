#pragma once
#include "Compiler/ModuleApi/ModuleApi.Source.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace ModuleApi
{
    inline TokenRef matchingModuleApiDelimiter(const SourceView& srcView, TokenRef openRef, TokenId openId, TokenId closeId)
    {
        uint32_t balance = 0;
        for (uint32_t tokIndex = openRef.get(); tokIndex < srcView.tokens().size(); ++tokIndex)
        {
            const TokenId tokenId = srcView.token(TokenRef(tokIndex)).id;
            if (tokenId == openId)
                balance++;
            else if (tokenId == closeId)
            {
                SWC_ASSERT(balance != 0);
                balance--;
                if (!balance)
                    return TokenRef(tokIndex);
            }
        }

        return TokenRef::invalid();
    }

    bool       isDeclarationWrapper(const AstNode& node);
    AstNodeRef findEnclosingImplRef(const SourceFile& file, AstNodeRef declRef);
    bool       hasExplicitPublicAccessModifier(const SourceFile& file, AstNodeRef declRef);
    bool       isExportedPublicDeclScope(const SourceFile& file, AstNodeRef declRef, const Symbol& symbol);
    bool       extractPublicNamespacePath(TaskContext& ctx, const SourceFile& file, AstNodeRef declRef, const Symbol& symbol, std::vector<IdentifierRef>& outNamespacePath);
    Result     resolvePendingEntries(TaskContext& ctx, ModuleApiFileEntries& entries, bool diagnosticsOnly);
}

SWC_END_NAMESPACE();
