#include "pch.h"
#include "Format/FormatPasses.h"
#include "Format/FormatPassUtil.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using FormatPassUtil::INVALID_PIECE;

    bool isSeparatorChar(const char c)
    {
        return c == '-' || c == '=' || c == '#' || c == '*' || c == '~' || c == '_';
    }

    // `// ------` style banners: only separator characters after the prefix.
    bool isSectionSeparator(const std::string_view text, char& outChar)
    {
        if (!text.starts_with("//"))
            return false;

        std::string_view body = text.substr(2);
        while (!body.empty() && (body.front() == ' ' || body.front() == '/'))
            body = body.substr(1);
        if (body.size() < 4)
            return false;

        const char c = body.front();
        if (!isSeparatorChar(c))
            return false;
        for (const char cur : body)
        {
            if (cur != c)
                return false;
        }

        outChar = c;
        return true;
    }

    // Marker comments (`swc-format off/on`) must never be rewritten.
    bool isFormatMarker(const FormatModel& model, const std::string_view text)
    {
        const FormatOptions& options = model.options();
        if (!options.formatOffComment.empty() && text.contains(options.formatOffComment.view()))
            return true;
        if (!options.formatOnComment.empty() && text.contains(options.formatOnComment.view()))
            return true;
        return false;
    }

    bool wantsSpaceAfterPrefix(const std::string_view text)
    {
        if (!text.starts_with("//"))
            return false;
        const std::string_view body = text.substr(2);
        if (body.empty())
            return false;

        // Doc / banner / directive prefixes keep their shape.
        const char c = body.front();
        if (c == ' ' || c == '\t' || c == '/' || c == '!' || c == '#')
            return false;
        if (isSeparatorChar(c))
            return false;
        return true;
    }

    void normalizePrefixes(FormatModel& model)
    {
        const FormatOptions& options   = model.options();
        const bool           normalize = options.spaceAfterLineCommentPrefix.value_or(false) ||
                                         options.commentReflow != FormatCommentReflow::Preserve;
        if (!normalize)
            return;

        for (uint32_t i = 0; i < model.numPieces(); ++i)
        {
            const FormatPiece& piece = model.piece(i);
            if (piece.removed || piece.frozen || piece.isNot(TokenId::CommentLine))
                continue;
            if (isFormatMarker(model, piece.text))
                continue;
            if (!wantsSpaceAfterPrefix(piece.text))
                continue;

            Utf8 rewritten("// ");
            rewritten += piece.text.substr(2);
            model.replaceText(i, std::move(rewritten));
        }
    }

    void normalizeSeparators(FormatModel& model)
    {
        const FormatOptions& options = model.options();
        if (!options.normalizeSectionSeparators.value_or(false) || options.sectionSeparatorWidth < 8)
            return;

        for (uint32_t i = 0; i < model.numPieces(); ++i)
        {
            const FormatPiece& piece = model.piece(i);
            if (piece.removed || piece.frozen || piece.isNot(TokenId::CommentLine))
                continue;

            char sepChar = 0;
            if (!isSectionSeparator(piece.text, sepChar))
                continue;

            const bool hadSpace = piece.text.size() > 2 && piece.text[2] == ' ';
            Utf8       rewritten("//");
            uint32_t   used = 2;
            if (hadSpace)
            {
                rewritten += ' ';
                used++;
            }
            rewritten.append(std::max(options.sectionSeparatorWidth, used + 1u) - used, sepChar);
            model.replaceText(i, std::move(rewritten));
        }
    }

    struct Paragraph
    {
        std::vector<uint32_t> pieces;
    };

    // Reflows consecutive whole-line `//` comments to the column limit.
    void reflowParagraphs(FormatModel& model)
    {
        const FormatOptions& options = model.options();
        if (options.commentReflow != FormatCommentReflow::Reflow || options.columnLimit == 0)
            return;

        std::vector<uint32_t> lineStarts;
        model.collectLineStarts(lineStarts);

        std::vector<Paragraph> paragraphs;
        Paragraph              current;

        auto flush = [&]() {
            if (current.pieces.size() > 1)
                paragraphs.push_back(current);
            current.pieces.clear();
        };

        for (size_t l = 0; l < lineStarts.size(); ++l)
        {
            const uint32_t     lineStart = lineStarts[l];
            const FormatPiece& piece     = model.piece(lineStart);

            const bool wholeLineComment = piece.is(TokenId::CommentLine) &&
                                          FormatPassUtil::lineEndOf(model, lineStart) == lineStart;
            char sepChar = 0;
            if (!wholeLineComment || piece.frozen || model.gapBefore(lineStart).frozen ||
                isFormatMarker(model, piece.text) || isSectionSeparator(piece.text, sepChar) ||
                !piece.text.starts_with("// ") ||
                (!current.pieces.empty() && model.gapNewlineCount(lineStart) > 1))
            {
                flush();
                continue;
            }

            current.pieces.push_back(lineStart);
        }
        flush();

        const uint32_t tabWidth = std::max(options.tabWidth, 1u);
        for (const Paragraph& paragraph : paragraphs)
        {
            // Collect the words of the whole paragraph.
            std::vector<std::string_view> words;
            for (const uint32_t pieceIndex : paragraph.pieces)
            {
                std::string_view body = model.piece(pieceIndex).text.substr(3);
                while (!body.empty())
                {
                    const size_t wordStart = body.find_first_not_of(" \t");
                    if (wordStart == std::string_view::npos)
                        break;
                    body                = body.substr(wordStart);
                    const size_t wordEnd = body.find_first_of(" \t");
                    words.push_back(body.substr(0, wordEnd == std::string_view::npos ? body.size() : wordEnd));
                    body = wordEnd == std::string_view::npos ? std::string_view{} : body.substr(wordEnd);
                }
            }
            if (words.empty())
                continue;

            const uint32_t startCol = FormatModel::textColumns(model.lineIndentOf(paragraph.pieces.front()), tabWidth);
            const uint32_t budget   = options.columnLimit > startCol + 8 ? options.columnLimit - startCol : 8;

            // Rebuild the lines.
            std::vector<Utf8> lines;
            Utf8              line("// ");
            uint32_t          lineCols = 3;
            for (const std::string_view word : words)
            {
                const uint32_t wordCols = FormatModel::textColumns(word, tabWidth);
                if (lineCols > 3 && lineCols + 1 + wordCols > budget)
                {
                    lines.push_back(std::move(line));
                    line     = "// ";
                    lineCols = 3;
                }
                if (lineCols > 3)
                {
                    line += ' ';
                    lineCols++;
                }
                line += word;
                lineCols += wordCols;
            }
            lines.push_back(std::move(line));

            if (lines.size() == paragraph.pieces.size())
            {
                bool unchanged = true;
                for (size_t i = 0; i < lines.size(); ++i)
                {
                    if (lines[i].view() != model.piece(paragraph.pieces[i]).text)
                        unchanged = false;
                }
                if (unchanged)
                    continue;
            }

            // Distribute the rebuilt lines over the existing comment pieces;
            // extra lines are folded into the last piece, extra pieces removed.
            const Utf8 indent(model.lineIndentOf(paragraph.pieces.front()));
            const size_t reused = std::min(lines.size(), paragraph.pieces.size());
            for (size_t i = 0; i < reused; ++i)
            {
                Utf8 text = lines[i];
                if (i + 1 == reused && lines.size() > reused)
                {
                    for (size_t extra = reused; extra < lines.size(); ++extra)
                    {
                        text += model.eol();
                        text += indent;
                        text += lines[extra];
                    }
                }
                model.replaceText(paragraph.pieces[i], std::move(text));
            }
            for (size_t i = reused; i < paragraph.pieces.size(); ++i)
                model.removePiece(paragraph.pieces[i]);
        }
    }
}

namespace FormatPass
{
    void comments(FormatModel& model)
    {
        normalizePrefixes(model);
        normalizeSeparators(model);
        reflowParagraphs(model);
    }
}

SWC_END_NAMESPACE();
