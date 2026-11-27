#include "pch.h"
#include "Format/FormatPassUtil.h"
#include "Format/FormatPasses.h"
#include "Format/FormatSiblings.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using FormatPassUtil::INVALID_PIECE;
    using FormatSiblings::BodyShape;

    // Normalize related function bodies to either `{ return e }` or `=> e`.
    // The caller reparses rewritten text before layout.
    class UniformPass
    {
    public:
        explicit UniformPass(FormatModel& model) :
            model_(&model),
            options_(&model.options())
        {
        }

        bool run()
        {
            rewriteClosures();
            rewriteFunctions();

            return changed_;
        }

    private:
        // Closes a body that gains braces right after its last piece.
        void appendClose(const uint32_t last)
        {
            Utf8 text(model_->piece(last).text);
            text += model_->eol();
            text += "}";
            model_->replaceText(last, std::move(text));

            // Render the appended brace as plain text even when the original piece
            // was a number; the subsequent parse will classify it again.
            model_->piece(last).id = TokenId::Identifier;
        }

        // `{ return e }` -> `=> e`.
        bool canUnbraceFunction(const FormatFunctionBody& body, const BodyShape& shape) const
        {
            if (!shape.braced || !shape.unbraceable)
                return false;

            const uint32_t prev = model_->prevPiece(body.openPiece);
            return prev != INVALID_PIECE && !model_->piece(prev).isComment;
        }

        void unbraceFunction(const FormatFunctionBody& body, const BodyShape& shape)
        {
            model_->replaceText(body.openPiece, Utf8("=>"));
            model_->setGapSpaces(body.openPiece, 1);
            model_->removePiece(shape.first);
            model_->removePiece(body.lastPiece);
            changed_ = true;
        }

        void rewriteClosures()
        {
            const auto& bodies = model_->functionBodies();
            for (const auto& group : FormatSiblings::closureGroups(*model_, options_->uniformClosureBodies))
            {
                FormatSiblings::BodyGroupShape shapeGroup;
                std::vector<BodyShape>         shapes;
                for (const uint32_t i : group)
                {
                    shapes.push_back(FormatSiblings::functionShape(*model_, bodies[i]));
                    const BodyShape& shape = shapes.back();
                    shapeGroup.add(shape);
                }

                if (!shapeGroup.oneLine || !shapeGroup.expanded)
                    continue;

                for (size_t i = 0; i < group.size(); ++i)
                {
                    const FormatFunctionBody& body  = bodies[group[i]];
                    const BodyShape&          shape = shapes[i];

                    if (shapeGroup.compact)
                    {
                        if (shape.valid && canUnbraceFunction(body, shape))
                            unbraceFunction(body, shape);

                        continue;
                    }

                    if (shape.braced || !shape.valid || !shape.braceable)
                        continue;

                    Utf8 open("{");
                    open += model_->eol();
                    open += "return";
                    model_->replaceText(body.arrowPiece, std::move(open));
                    appendClose(shape.last);
                    changed_ = true;
                }
            }
        }

        // Single-statement functions declared side by side, some already on
        // one line: `{ return e }` becomes `=> e`. The layout pass joins the
        // bodies that return nothing.
        void rewriteFunctions()
        {
            const auto& bodies = model_->functionBodies();
            for (const auto& group : FormatSiblings::functionGroups(*model_, options_->uniformFunctionBodies))
            {
                FormatSiblings::BodyGroupShape shapeGroup;
                std::vector<BodyShape>         shapes;
                for (const uint32_t i : group)
                {
                    shapes.push_back(FormatSiblings::functionShape(*model_, bodies[i]));
                    const BodyShape& shape = shapes.back();
                    shapeGroup.add(shape, true);
                }

                if (!shapeGroup.oneLine || !shapeGroup.expanded || !shapeGroup.compact)
                    continue;

                for (size_t i = 0; i < group.size(); ++i)
                {
                    if (canUnbraceFunction(bodies[group[i]], shapes[i]))
                        unbraceFunction(bodies[group[i]], shapes[i]);
                }
            }
        }

        FormatModel*         model_;
        const FormatOptions* options_;

        bool changed_ = false;
    };
}

namespace FormatPass
{
    bool uniformSiblings(FormatModel& model)
    {
        return UniformPass(model).run();
    }
}

SWC_END_NAMESPACE();
