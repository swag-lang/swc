#global internal
#global namespace Pipeline

using Core, Gui

/*
The stages Swag Prism offers, in the order the compiler reaches them.

A stage is a pass of the backend with the side it is read from, which is exactly the spelling
`Swag.PrintMicro` takes: the attribute prints one function's instructions before or after any named
pass, so `post-licm` is the code once the loop-invariant motion has run.

This is a chosen path through the backend rather than every pass it runs. The pane tells the story
of what happens to one function, and a complete pass list tells that story worse: most passes leave
any given function untouched, and a reader stepping through twenty of those learns nothing between
the two that mattered.

The first entry is the code as it was generated, before anything optimized it, and the last is the
instruction list handed to the encoder.
*/
const Stages = [
    "pre-mem-to-reg",
    "post-mem-to-reg",
    "post-const-fold",
    "post-instcombine",
    "post-value-numbering",
    "post-strength-reduce",
    "post-loop-unroll",
    "post-licm",
    "post-slp-vectorize",
    "post-dce",
    "pre-regalloc",
    "post-regalloc",
    "post-post-ra-peephole",
    "pre-emit"]

// Index of the stage the window opens on.
//
// The final instruction list is what a reader wants first: it is the code that will run, and it is
// the one stage that means something without having seen any other.
const DefaultStage = 13'u32

/*
What each offered stage is called in the interface, in the order of [[Stages]].

The pass spelling above is what the compiler answers to and never changes with the language; this
is the sentence a reader picks from, so it does. The two tables are read together and a test pins
them to the same length.
*/
func stageLabels()->[Stages.count] string
{
    let strings = appStrings()
    return [
        strings.ui_StageGenerated,
        strings.ui_StageMemToReg,
        strings.ui_StageConstFold,
        strings.ui_StageInstCombine,
        strings.ui_StageValueNumbering,
        strings.ui_StageStrengthReduce,
        strings.ui_StageLoopUnroll,
        strings.ui_StageLicm,
        strings.ui_StageVectorize,
        strings.ui_StageDce,
        strings.ui_StageBeforeRegisters,
        strings.ui_StageRegalloc,
        strings.ui_StagePeephole,
        strings.ui_StageFinal]
}
