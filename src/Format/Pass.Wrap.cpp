#include "pch.h"
#include "Format/FormatPasses.h"
#include "Format/FormatPassUtil.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using FormatPassUtil::INVALID_PIECE;
    using FormatPassUtil::PieceColumn;

    class WrapPass
    {
    public:
        explicit WrapPass(FormatModel& model) :
            model_(&model),
            options_(&model.options())
        {
        }

        void run()
        {
            if (options_->columnLimit == 0)
                return;

            std::vector<uint32_t> lineStarts;
            model_->collectLineStarts(lineStarts);

            // Newly created lines are processed in turn: work on a queue.
            std::deque<uint32_t> queue(lineStarts.begin(), lineStarts.end());
            uint32_t             guard = 0;
            while (!queue.empty() && guard < 100000)
            {
                guard++;
                const uint32_t lineStart = queue.front();
                queue.pop_front();

                const uint32_t next = wrapLine(lineStart);
                if (next != INVALID_PIECE)
                    queue.push_front(next);
            }
        }

    private:
        bool lineEditable(const uint32_t lineStart) const
        {
            uint32_t piece = lineStart;
            for (;;)
            {
                if (model_->piece(piece).frozen || model_->gapBefore(piece).frozen)
                    return false;
                const uint32_t next = model_->nextPiece(piece);
                if (next == INVALID_PIECE || model_->gapHasNewline(next))
                    return true;
                piece = next;
            }
        }

        // Wraps one line; returns the start of the continuation line to
        // process next, or INVALID_PIECE when the line fits.
        uint32_t wrapLine(const uint32_t lineStart)
        {
            std::vector<PieceColumn> columns;
            const uint32_t           width = FormatPassUtil::computeLineColumns(*model_, lineStart, &columns);
            if (width <= options_->columnLimit || columns.size() < 2)
                return INVALID_PIECE;
            if (!lineEditable(lineStart))
                return INVALID_PIECE;

            const uint32_t breakPiece = chooseBreak(columns);
            if (breakPiece == INVALID_PIECE)
                return INVALID_PIECE;

            const Utf8 indent = continuationIndent(lineStart, columns, breakPiece);
            model_->setGapBreak(breakPiece, 1, indent.view());
            return breakPiece;
        }

        // Break candidates, by priority: after a comma at the lowest bracket
        // depth, then around binary operators, then before ternary operators,
        // before `->`, before a trailing `do`.
        uint32_t chooseBreak(const std::vector<PieceColumn>& columns) const
        {
            const uint32_t limit = options_->columnLimit;

            uint32_t bestComma      = INVALID_PIECE;
            uint32_t bestCommaDepth = UINT32_MAX;
            uint32_t bestOp         = INVALID_PIECE;
            uint32_t bestOther      = INVALID_PIECE;

            const FormatOperatorWrapStyle opStyle = options_->breakBeforeBinaryOperators;

            // Find the lowest depth of a comma candidate on the line.
            for (const auto& [pieceIndex, column] : columns)
            {
                const FormatPiece& piece = model_->piece(pieceIndex);
                if (piece.is(TokenId::SymComma))
                    bestCommaDepth = std::min(bestCommaDepth, piece.depth);
            }

            // Pick the last candidate that still fits the limit; fall back to
            // the first candidate otherwise.
            uint32_t firstAny = INVALID_PIECE;
            for (size_t c = 0; c < columns.size(); ++c)
            {
                const auto& [pieceIndex, column] = columns[c];
                const FormatPiece& piece         = model_->piece(pieceIndex);

                uint32_t candidate = INVALID_PIECE; // piece that will start the next line

                if (piece.is(TokenId::SymComma) && piece.depth == bestCommaDepth && c + 1 < columns.size())
                    candidate = columns[c + 1].piece; // break after the comma
                else if (piece.hasRole(FormatRoleE::BinaryOp) && opStyle != FormatOperatorWrapStyle::Preserve && opStyle != FormatOperatorWrapStyle::None)
                {
                    if (opStyle == FormatOperatorWrapStyle::Before)
                        candidate = pieceIndex;
                    else if (c + 1 < columns.size())
                        candidate = columns[c + 1].piece;
                }
                else if (piece.hasRole(FormatRoleE::TernaryOp) && options_->breakBeforeTernaryOperators.value_or(false))
                    candidate = pieceIndex;
                else if (piece.hasRole(FormatRoleE::Arrow) && options_->breakAfterReturnType.value_or(false))
                    candidate = pieceIndex;
                else if (piece.hasRole(FormatRoleE::TrailingDo) && options_->breakBeforeDo.value_or(false))
                    candidate = pieceIndex;

                if (candidate == INVALID_PIECE || candidate == columns.front().piece)
                    continue;
                if (model_->piece(candidate).isComment)
                    continue;

                if (firstAny == INVALID_PIECE)
                    firstAny = candidate;

                // The break must leave the head part within the limit.
                if (column < limit)
                {
                    if (piece.is(TokenId::SymComma) && piece.depth == bestCommaDepth)
                        bestComma = candidate;
                    else if (piece.hasRole(FormatRoleE::BinaryOp))
                        bestOp = candidate;
                    else
                        bestOther = candidate;
                }
            }

            if (bestComma != INVALID_PIECE)
                return bestComma;
            if (bestOp != INVALID_PIECE)
                return bestOp;
            if (bestOther != INVALID_PIECE)
                return bestOther;
            return firstAny;
        }

        Utf8 continuationIndent(const uint32_t lineStart, const std::vector<PieceColumn>& columns, const uint32_t breakPiece) const
        {
            if (options_->alignAfterOpenBracket.value_or(false))
            {
                // Align with the innermost bracket left open before the break.
                uint32_t openColumn = UINT32_MAX;
                std::vector<uint32_t> stack;
                for (const auto& [pieceIndex, column] : columns)
                {
                    if (pieceIndex == breakPiece)
                        break;
                    const FormatPiece& piece = model_->piece(pieceIndex);
                    if (piece.is(TokenId::SymLeftParen) || piece.is(TokenId::SymLeftBracket))
                        stack.push_back(column);
                    else if (piece.is(TokenId::SymRightParen) || piece.is(TokenId::SymRightBracket))
                    {
                        if (!stack.empty())
                            stack.pop_back();
                    }
                }
                if (!stack.empty())
                    openColumn = stack.back();

                if (openColumn != UINT32_MAX)
                    return FormatPassUtil::indentForColumns(*model_, openColumn + 1);
            }

            const uint32_t tabWidth = std::max(options_->tabWidth, 1u);
            const uint32_t baseCols = FormatModel::textColumns(model_->lineIndentOf(lineStart), tabWidth);
            return FormatPassUtil::indentForColumns(*model_, baseCols + std::max(options_->continuationIndentWidth, 1u));
        }

        // One-per-line argument packing: once a call or declaration argument
        // list wraps, every top-level comma of that list breaks.
        void applyBinPack(const uint32_t openPiece, const FormatBinPackStyle style)
        {
            if (style != FormatBinPackStyle::OnePerLine)
                return;

            const FormatPiece& open = model_->piece(openPiece);
            if (open.match == INVALID_PIECE)
                return;

            // Only when the list already spans several lines; reuse the indent
            // of the first existing continuation line.
            uint32_t firstContinuation = INVALID_PIECE;
            for (uint32_t i = openPiece + 1; i <= open.match; ++i)
            {
                if (!model_->piece(i).removed && model_->gapHasNewline(i))
                {
                    firstContinuation = i;
                    break;
                }
            }
            if (firstContinuation == INVALID_PIECE)
                return;

            const Utf8     indent(model_->lineIndentOf(firstContinuation));
            const uint32_t innerDepth = open.depth + 1;
            for (uint32_t i = openPiece + 1; i < open.match; ++i)
            {
                const FormatPiece& piece = model_->piece(i);
                if (piece.removed || piece.isNot(TokenId::SymComma) || piece.depth != innerDepth)
                    continue;
                const uint32_t next = model_->nextPiece(i);
                if (next == INVALID_PIECE || next >= open.match)
                    continue;
                if (model_->gapHasNewline(next) || !FormatPassUtil::canEditGap(*model_, next))
                    continue;
                model_->setGapBreak(next, 1, indent.view());
            }
        }

    public:
        void runBinPack()
        {
            const bool wantArgs   = options_->binPackArguments == FormatBinPackStyle::OnePerLine;
            const bool wantParams = options_->binPackParameters == FormatBinPackStyle::OnePerLine;
            if (!wantArgs && !wantParams)
                return;

            for (uint32_t i = 0; i < model_->numPieces(); ++i)
            {
                const FormatPiece& piece = model_->piece(i);
                if (piece.removed || piece.frozen)
                    continue;
                if (wantArgs && piece.hasRole(FormatRoleE::CallOpenParen))
                    applyBinPack(i, options_->binPackArguments);
                else if (wantParams && piece.hasRole(FormatRoleE::DeclOpenParen))
                    applyBinPack(i, options_->binPackParameters);
            }
        }

    private:
        FormatModel*         model_;
        const FormatOptions* options_;
    };
}

namespace FormatPass
{
    void wrap(FormatModel& model)
    {
        WrapPass pass(model);
        pass.runBinPack();
        pass.run();
    }
}

SWC_END_NAMESPACE();
