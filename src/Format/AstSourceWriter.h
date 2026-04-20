#pragma once
#include "Compiler/Lexer/Token.h"
#include "Compiler/Parser/Ast/AstNode.h"
#include "Format/FormatOptions.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class Ast;
class SourceView;

struct FormatContext
{
    const Ast*           ast     = nullptr;
    const SourceView*    srcView = nullptr;
    const FormatOptions* options = nullptr;
    Utf8                 output;
};

class AstSourceWriter
{
public:
    explicit AstSourceWriter(FormatContext& formatCtx);
    void write();

private:
    struct SourcePiece
    {
        uint32_t         byteStart  = 0;
        uint32_t         byteLength = 0;
        TokenId          tokenId    = TokenId::Invalid;
        std::string_view text;
    };

    static constexpr uint32_t INVALID_BYTE = 0xFFFFFFFFu;

    void             beginOutput();
    void             finalizeOutput() const;
    void             writeNode(AstNodeRef nodeRef);
    void             writeNodeChildren(const AstNode& node);
    void             collectSourceOrderedChildren(SmallVector<AstNodeRef>& out, const AstNode& node) const;
    bool             shouldVisitNode(AstNodeRef nodeRef) const;
    bool             hasCheckpoint(const AstNode& node) const;
    uint32_t         nodeCheckpointByte(AstNodeRef nodeRef) const;
    uint32_t         nodeSortByte(AstNodeRef nodeRef) const;
    void             flushUntilByte(uint32_t targetByte);
    SourcePiece      peekNextSourcePiece() const;
    void             appendNextSourcePiece();
    void             appendSourcePiece(const SourcePiece& piece);
    bool             shouldRewriteIndentation() const;
    bool             shouldRewriteEndOfLine() const;
    bool             hasTrailingLineBreak() const;
    bool             isAtLineStart() const;
    void             appendWhitespacePiece(const SourcePiece& piece) const;
    void             appendCommentPiece(const SourcePiece& piece) const;
    void             appendNumberPiece(const SourcePiece& piece) const;
    void             appendNormalizedIndent(std::string_view text) const;
    void             appendConfiguredEndOfLine() const;
    std::string_view resolveFinalNewline() const;
    SourcePiece      makeTriviaPiece(uint32_t triviaIndex) const;
    SourcePiece      makeTokenPiece(uint32_t tokenIndex) const;

    FormatContext*       formatCtx_       = nullptr;
    const Ast*           ast_             = nullptr;
    const SourceView*    srcView_         = nullptr;
    const FormatOptions* options_         = nullptr;
    uint32_t             cursorByte_      = 0;
    uint32_t             nextTokenIndex_  = 0;
    uint32_t             nextTriviaIndex_ = 0;
    uint32_t             eofByte_         = 0;
};

SWC_END_NAMESPACE();
