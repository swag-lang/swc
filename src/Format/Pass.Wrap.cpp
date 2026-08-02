#include "pch.h"
#include "Format/FormatPassUtil.h"
#include "Format/FormatPasses.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using FormatPassUtil::INVALID_PIECE;
    using FormatPassUtil::PieceColumn;

    enum class ListLineMode : uint8_t
    {
        Unchanged,
        SingleLine,
        MultiLine,
    };

    struct ListPolicy
    {
        std::optional<bool> forceSingleLine;
        std::optional<bool> sourceSelectsLayout;
        FormatListLayout    layout  = FormatListLayout::Preserve;
        FormatBinPackStyle  binPack = FormatBinPackStyle::Preserve;

        bool active() const
        {
            return forceSingleLine.value_or(false) || sourceSelectsLayout.has_value() ||
                   layout != FormatListLayout::Preserve || binPack != FormatBinPackStyle::Preserve;
        }
    };

    struct ListState
    {
        uint32_t              openPiece  = INVALID_PIECE;
        uint32_t              closePiece = INVALID_PIECE;
        std::vector<uint32_t> items;
        std::optional<bool>   forceSingleLine;
        std::optional<bool>   sourceSelectsLayout;
        FormatListLayout      layout     = FormatListLayout::Preserve;
        FormatBinPackStyle    binPack    = FormatBinPackStyle::Preserve;
        ListLineMode          lineMode   = ListLineMode::Unchanged;
        bool                  editable   = false;
        bool                  hasComment = false;
        bool                  canJoin    = false;
    };

    bool textHasNewline(const std::string_view text)
    {
        return text.find_first_of("\r\n") != std::string_view::npos;
    }

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
            collectLists();
            chooseLineModes();
            prepareLists();
            wrapLongLines();
            finishLists();
        }

    private:
        ListPolicy policyFor(const FormatPiece& piece) const
        {
            if (piece.hasRole(FormatRoleE::CallOpenParen))
            {
                return {
                    .forceSingleLine     = options_->forceSingleLineArgumentLists,
                    .sourceSelectsLayout = options_->sourceSelectsArgumentLayout,
                    .layout              = options_->argumentListLayout,
                    .binPack             = options_->binPackArguments,
                };
            }

            SWC_ASSERT(piece.hasRole(FormatRoleE::DeclOpenParen));
            return {
                .forceSingleLine     = options_->forceSingleLineParameterLists,
                .sourceSelectsLayout = options_->sourceSelectsParameterLayout,
                .layout              = options_->parameterListLayout,
                .binPack             = options_->binPackParameters,
            };
        }

        void collectLists()
        {
            for (uint32_t i = 0; i < model_->numPieces(); ++i)
            {
                const FormatPiece& open = model_->piece(i);
                if (open.removed || open.match == INVALID_PIECE ||
                    !open.roles.hasAny({FormatRoleE::CallOpenParen, FormatRoleE::DeclOpenParen}))
                    continue;

                const ListPolicy policy = policyFor(open);
                if (!policy.active())
                    continue;

                ListState state;
                state.openPiece           = i;
                state.closePiece          = open.match;
                state.forceSingleLine     = policy.forceSingleLine;
                state.sourceSelectsLayout = policy.sourceSelectsLayout;
                state.layout              = policy.layout;
                state.binPack             = policy.binPack;
                collectItems(state);
                lists_.push_back(std::move(state));
            }
        }

        void chooseLineModes()
        {
            // Normalize nested lists first so an outer list can join when all
            // of its intrinsically multiline children can also join.
            for (auto it = lists_.rbegin(); it != lists_.rend(); ++it)
            {
                inspectList(*it);
                chooseLineMode(*it);
            }
        }

        void collectItems(ListState& state) const
        {
            const FormatPiece& open = model_->piece(state.openPiece);
            uint32_t           item = model_->nextPiece(state.openPiece);
            if (item == INVALID_PIECE || item == state.closePiece)
                return;
            state.items.push_back(item);

            const uint32_t innerDepth = open.depth + 1;
            for (uint32_t i = item; i != INVALID_PIECE && i < state.closePiece; i = model_->nextPiece(i))
            {
                const FormatPiece& piece = model_->piece(i);
                if (piece.isNot(TokenId::SymComma) || piece.depth != innerDepth)
                    continue;

                const uint32_t next = model_->nextPiece(i);
                if (next != INVALID_PIECE && next < state.closePiece)
                    state.items.push_back(next);
            }
        }

        bool isItemStart(const ListState& state, const uint32_t pieceIndex) const
        {
            return std::ranges::find(state.items, pieceIndex) != state.items.end();
        }

        void inspectList(ListState& state) const
        {
            state.editable = FormatPassUtil::canEditPiece(*model_, state.openPiece) &&
                             FormatPassUtil::canEditPiece(*model_, state.closePiece);
            state.canJoin = state.editable;

            for (uint32_t i = state.openPiece + 1; i <= state.closePiece; ++i)
            {
                const FormatPiece& piece = model_->piece(i);
                if (piece.removed)
                    continue;
                if (piece.isComment)
                {
                    state.hasComment = true;
                    state.canJoin    = false;
                }
                if (piece.frozen || model_->gapBefore(i).frozen)
                {
                    state.editable = false;
                    state.canJoin  = false;
                }

                if (model_->gapHasNewline(i) && i != state.closePiece && !isItemStart(state, i))
                    state.canJoin = false;
            }
        }

        bool firstItemsShareSourceLine(const ListState& state) const
        {
            if (state.items.size() < 2)
                return true;

            for (uint32_t i = state.items[0] + 1; i <= state.items[1]; ++i)
            {
                if (textHasNewline(model_->gapBefore(i).origText))
                    return false;
            }
            return true;
        }

        std::vector<FormatGap> snapshotGaps(const ListState& state) const
        {
            std::vector<FormatGap> result;
            result.reserve(state.closePiece - state.openPiece);
            for (uint32_t i = state.openPiece + 1; i <= state.closePiece; ++i)
                result.push_back(model_->gapBefore(i));
            return result;
        }

        void restoreGaps(const ListState& state, const std::vector<FormatGap>& gaps) const
        {
            SWC_ASSERT(gaps.size() == state.closePiece - state.openPiece);
            for (uint32_t i = state.openPiece + 1; i <= state.closePiece; ++i)
                model_->gapBefore(i) = gaps[i - state.openPiece - 1];
        }

        uint32_t spacesAfterOpen() const
        {
            return options_->spaceInsideParentheses.value_or(false) ? 1 : 0;
        }

        uint32_t spacesAfterComma() const
        {
            return options_->spaceAfterComma.value_or(true) ? 1 : 0;
        }

        uint32_t spacesBeforeClose(const ListState& state) const
        {
            if (state.items.empty())
                return options_->spaceInEmptyParentheses.value_or(false) ? 1 : 0;
            return options_->spaceInsideParentheses.value_or(false) ? 1 : 0;
        }

        bool joinList(const ListState& state) const
        {
            if (!state.canJoin)
                return false;

            for (size_t i = 0; i < state.items.size(); ++i)
            {
                const uint32_t item = state.items[i];
                if (!model_->gapHasNewline(item))
                    continue;
                model_->setGapSpaces(item, i == 0 ? spacesAfterOpen() : spacesAfterComma());
            }

            if (model_->gapHasNewline(state.closePiece))
                model_->setGapSpaces(state.closePiece, spacesBeforeClose(state));
            return true;
        }

        bool joinedListFits(const ListState& state) const
        {
            if (options_->columnLimit == 0)
                return true;
            const uint32_t lineStart = model_->lineStartOf(state.openPiece);
            return FormatPassUtil::lineWidth(*model_, lineStart) <= options_->columnLimit;
        }

        void chooseLineMode(ListState& state)
        {
            if (!state.editable)
                return;

            if (state.forceSingleLine.value_or(false))
            {
                if (joinList(state))
                    state.lineMode = ListLineMode::SingleLine;
                return;
            }

            if (!state.sourceSelectsLayout.has_value())
                return;

            if (*state.sourceSelectsLayout)
            {
                if (firstItemsShareSourceLine(state) && joinList(state))
                    state.lineMode = ListLineMode::SingleLine;
                else
                    state.lineMode = ListLineMode::MultiLine;
                return;
            }

            if (!state.canJoin)
            {
                state.lineMode = ListLineMode::MultiLine;
                return;
            }

            const std::vector<FormatGap> originalGaps = snapshotGaps(state);
            const bool                   joined       = joinList(state);
            SWC_ASSERT(joined);
            if (joinedListFits(state))
            {
                state.lineMode = ListLineMode::SingleLine;
                return;
            }

            restoreGaps(state, originalGaps);
            state.lineMode = ListLineMode::MultiLine;
        }

        bool listIsMultiline(const ListState& state) const
        {
            for (uint32_t i = state.openPiece + 1; i <= state.closePiece; ++i)
            {
                if (!model_->piece(i).removed && model_->gapHasNewline(i))
                    return true;
            }
            return false;
        }

        Utf8 fixedContinuationIndent(const ListState& state) const
        {
            const uint32_t tabWidth = std::max(options_->tabWidth, 1u);
            const uint32_t baseCols = FormatModel::textColumns(model_->lineIndentOf(state.openPiece), tabWidth);
            return FormatPassUtil::indentForColumns(*model_, baseCols + std::max(options_->continuationIndentWidth, 1u));
        }

        uint32_t openColumn(const ListState& state) const
        {
            std::vector<PieceColumn> columns;
            FormatPassUtil::computeLineColumns(*model_, model_->lineStartOf(state.openPiece), &columns);
            for (const PieceColumn& column : columns)
            {
                if (column.piece == state.openPiece)
                    return column.column;
            }
            return UINT32_MAX;
        }

        Utf8 listItemIndent(const ListState& state) const
        {
            if (state.layout == FormatListLayout::HangingAlign)
            {
                const uint32_t column = openColumn(state);
                if (column != UINT32_MAX)
                    return FormatPassUtil::indentForColumns(*model_, column + 1);
            }

            if (state.layout == FormatListLayout::Preserve)
            {
                for (const uint32_t item : state.items)
                {
                    if (model_->gapHasNewline(item))
                        return Utf8(model_->lineIndentOf(item));
                }
            }

            return fixedContinuationIndent(state);
        }

        void attachFirstItem(const ListState& state) const
        {
            if (state.items.empty() || state.hasComment)
                return;
            const uint32_t first = state.items.front();
            if (model_->gapHasNewline(first) && FormatPassUtil::canEditGap(*model_, first))
                model_->setGapSpaces(first, spacesAfterOpen());
        }

        void breakFirstItem(const ListState& state) const
        {
            if (state.items.empty() || state.hasComment)
                return;
            const uint32_t first = state.items.front();
            if (FormatPassUtil::canEditGap(*model_, first))
                model_->setGapBreak(first, 1, fixedContinuationIndent(state).view());
        }

        void applyListShape(const ListState& state) const
        {
            switch (state.layout)
            {
                case FormatListLayout::HangingIndent:
                case FormatListLayout::HangingAlign:
                    attachFirstItem(state);
                    break;
                case FormatListLayout::Vertical:
                case FormatListLayout::Block:
                    breakFirstItem(state);
                    break;
                case FormatListLayout::Preserve:
                    break;
            }
        }

        uint32_t requiredPackedBreak(const ListState& state) const
        {
            if (state.items.empty())
                return INVALID_PIECE;
            if (state.layout == FormatListLayout::Vertical || state.layout == FormatListLayout::Block)
                return state.items.front();
            if ((state.layout == FormatListLayout::HangingIndent || state.layout == FormatListLayout::HangingAlign) && state.items.size() > 1)
                return state.items[1];

            for (const uint32_t item : state.items)
            {
                if (model_->gapHasNewline(item))
                    return item;
            }
            return INVALID_PIECE;
        }

        void packExistingLines(const ListState& state) const
        {
            if (state.binPack != FormatBinPackStyle::Pack || state.hasComment || !listIsMultiline(state))
                return;

            const uint32_t requiredBreak = requiredPackedBreak(state);
            for (size_t i = 0; i < state.items.size(); ++i)
            {
                const uint32_t item = state.items[i];
                if (item == requiredBreak || !model_->gapHasNewline(item) || !FormatPassUtil::canEditGap(*model_, item))
                    continue;
                model_->setGapSpaces(item, i == 0 ? spacesAfterOpen() : spacesAfterComma());
            }
        }

        void prepareLists()
        {
            for (const ListState& state : lists_)
            {
                if (state.lineMode == ListLineMode::SingleLine)
                    continue;
                if (state.lineMode == ListLineMode::MultiLine || listIsMultiline(state))
                    applyListShape(state);
                packExistingLines(state);
            }
        }

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

        bool commaBelongsToSingleLineList(const uint32_t commaPiece) const
        {
            for (auto it = lists_.rbegin(); it != lists_.rend(); ++it)
            {
                const ListState& state = *it;
                if (state.lineMode != ListLineMode::SingleLine || commaPiece <= state.openPiece || commaPiece >= state.closePiece)
                    continue;
                if (model_->piece(commaPiece).depth == model_->piece(state.openPiece).depth + 1)
                    return true;
            }
            return false;
        }

        const ListState* listContaining(const uint32_t pieceIndex) const
        {
            for (auto it = lists_.rbegin(); it != lists_.rend(); ++it)
            {
                if (pieceIndex > it->openPiece && pieceIndex < it->closePiece)
                    return &*it;
            }
            return nullptr;
        }

        void wrapLongLines()
        {
            if (options_->columnLimit == 0)
                return;

            std::vector<uint32_t> lineStarts;
            model_->collectLineStarts(lineStarts);

            std::deque queue(lineStarts.begin(), lineStarts.end());
            uint32_t   guard = 0;
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

        uint32_t wrapLine(const uint32_t lineStart) const
        {
            std::vector<PieceColumn> columns;
            const uint32_t           width = FormatPassUtil::computeLineColumns(*model_, lineStart, &columns);
            if (width <= options_->columnLimit || columns.size() < 2 || !lineEditable(lineStart))
                return INVALID_PIECE;

            const uint32_t breakPiece = chooseBreak(columns);
            if (breakPiece == INVALID_PIECE)
                return INVALID_PIECE;

            const Utf8 indent = continuationIndent(lineStart, columns, breakPiece);
            model_->setGapBreak(breakPiece, 1, indent.view());
            return breakPiece;
        }

        uint32_t chooseBreak(const std::vector<PieceColumn>& columns) const
        {
            const uint32_t limit = options_->columnLimit;

            uint32_t bestComma      = INVALID_PIECE;
            uint32_t bestCommaDepth = UINT32_MAX;
            uint32_t bestOp         = INVALID_PIECE;
            uint32_t bestOther      = INVALID_PIECE;

            const FormatOperatorWrapStyle opStyle = options_->breakBeforeBinaryOperators;

            for (const auto& [pieceIndex, column] : columns)
            {
                const FormatPiece& piece = model_->piece(pieceIndex);
                if (piece.is(TokenId::SymComma) && !commaBelongsToSingleLineList(pieceIndex))
                    bestCommaDepth = std::min(bestCommaDepth, piece.depth);
            }

            uint32_t firstAny = INVALID_PIECE;
            for (size_t c = 0; c < columns.size(); ++c)
            {
                const auto& [pieceIndex, column] = columns[c];
                const FormatPiece& piece         = model_->piece(pieceIndex);

                uint32_t candidate = INVALID_PIECE;
                if (piece.is(TokenId::SymComma) && piece.depth == bestCommaDepth &&
                    !commaBelongsToSingleLineList(pieceIndex) && c + 1 < columns.size())
                    candidate = columns[c + 1].piece;
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

                if (candidate == INVALID_PIECE || candidate == columns.front().piece || model_->piece(candidate).isComment)
                    continue;
                if (firstAny == INVALID_PIECE)
                    firstAny = candidate;

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
            const ListState* list = listContaining(breakPiece);
            if (list && list->lineMode != ListLineMode::SingleLine && list->layout != FormatListLayout::Preserve)
                return listItemIndent(*list);

            if (options_->alignAfterOpenBracket.value_or(false))
            {
                uint32_t              openBracketColumn = UINT32_MAX;
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
                    openBracketColumn = stack.back();
                if (openBracketColumn != UINT32_MAX)
                    return FormatPassUtil::indentForColumns(*model_, openBracketColumn + 1);
            }

            const uint32_t tabWidth = std::max(options_->tabWidth, 1u);
            const uint32_t baseCols = FormatModel::textColumns(model_->lineIndentOf(lineStart), tabWidth);
            return FormatPassUtil::indentForColumns(*model_, baseCols + std::max(options_->continuationIndentWidth, 1u));
        }

        void applyOnePerLine(const ListState& state, const Utf8& indent) const
        {
            if (state.binPack != FormatBinPackStyle::OnePerLine || state.items.size() < 2 || state.hasComment)
                return;

            for (size_t i = 1; i < state.items.size(); ++i)
            {
                const uint32_t item = state.items[i];
                if (FormatPassUtil::canEditGap(*model_, item))
                    model_->setGapBreak(item, 1, indent.view());
            }
        }

        void alignBrokenItems(const ListState& state, const Utf8& indent) const
        {
            if (state.layout == FormatListLayout::Preserve || state.hasComment)
                return;

            for (const uint32_t item : state.items)
            {
                if (model_->gapHasNewline(item) && FormatPassUtil::canEditGap(*model_, item))
                    model_->setGapBreak(item, 1, indent.view());
            }
        }

        void placeClose(const ListState& state) const
        {
            if (state.hasComment || !FormatPassUtil::canEditGap(*model_, state.closePiece))
                return;

            if (state.layout == FormatListLayout::Block)
            {
                model_->setGapBreak(state.closePiece, 1, model_->lineIndentOf(state.openPiece));
                return;
            }

            if (state.layout != FormatListLayout::Preserve && model_->gapHasNewline(state.closePiece))
                model_->setGapSpaces(state.closePiece, spacesBeforeClose(state));
        }

        void finishLists() const
        {
            for (const ListState& state : lists_)
            {
                if (state.lineMode == ListLineMode::SingleLine || !listIsMultiline(state))
                    continue;

                applyListShape(state);
                const Utf8 indent = listItemIndent(state);
                applyOnePerLine(state, indent);
                alignBrokenItems(state, indent);
                placeClose(state);
            }
        }

        FormatModel*           model_;
        const FormatOptions*   options_;
        std::vector<ListState> lists_;
    };
}

namespace FormatPass
{
    void wrap(FormatModel& model)
    {
        WrapPass(model).run();
    }
}

SWC_END_NAMESPACE();
