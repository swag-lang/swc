#global public

using Core, Gui

// Visible strings of Swag Prism.
//
// The name of the application is a proper name, and the name a compiler stage is spelled with is
// what the reader types into the attribute, so neither is translated.
struct AppStrings
{
    ui_WindowTitle:        string = "Swag Prism — What the compiler makes of your code"     // Title of the application window.
    ui_Stage:              string = "Stage"                                                 // Label of the pipeline-stage selector.
    ui_Optimize:           string = "Optimization level"                                    // Tooltip of the backend optimization selector.
    ui_CompileVisible:     string = "Compile views"                                         // Compiles the visible viewers.
    ui_CompileVisibleHint: string = "Compile the source in the visible viewers."            // Describes the shared-source compile action.
    ui_OneViewer:          string = "Show one viewer"                                       // Returns to the single-viewer layout.
    ui_TwoViewers:         string = "Show two viewers"                                      // Opens the comparison beside the first viewer.
    ui_ViewerLayoutHint:   string = "Switch between one viewer and two side by side."       // Global layout action.
    ui_ViewerType:         string = "Viewer type"                                           // Selects the viewer hosted by this panel.
    ui_Microcode:          string = "Microcode"                                             // Name of the first supported viewer type.
    ui_RunningViewers:     string = "% viewers compiling"                                   // Global status with the number of running viewer jobs.
    ui_Working:            string = "Compiling…"                                            // Status while the compiler runs.
    ui_Ready:              string = "Ready"                                                 // Status before anything has been compiled.
    ui_NoOutput:           string = "No output for this stage."                             // Status when a compilation left the pane empty.
    ui_Stopped:            string = "Compilation stopped."                                  // Status when the compilation failed.
    ui_Done:               string = "Compiled in % ms"                                      // Status after a compilation that printed a stage, with how long the compiler took.
    ui_ProbeStopped:       string = "The compiler could not be started."                    // Status when the compiler process itself never ran.

    // What the empty output pane says before anything has been compiled into it.
    //
    // The pane never wraps — an instruction listing is a set of aligned columns — so this sentence
    // has to be short enough to sit in it at the narrowest width rather than trail off the edge.
    ui_OutputHint: string = "Compile to see the instructions."

    // One name per offered pipeline stage, in the order of `Pipeline.Stages`. Each says what the
    // code has had done to it by the time it is read, not which pass is about to run.
    ui_StageGenerated:       string = "Generated"                   // Code as it left the generator, before anything optimized it.
    ui_StageMemToReg:        string = "Stack slots promoted"        // After locals that never needed an address became registers.
    ui_StageConstFold:       string = "Constants folded"            // After expressions with known operands became their result.
    ui_StageInstCombine:     string = "Instructions combined"       // After neighbouring operations merged into single ones.
    ui_StageValueNumbering:  string = "Values numbered"             // After a value computed twice is computed once.
    ui_StageStrengthReduce:  string = "Strength reduced"            // After costly operations became cheaper equivalents.
    ui_StageLoopUnroll:      string = "Loops unrolled"              // After short loops were written out in full.
    ui_StageLicm:            string = "Loop invariants hoisted"     // After work that does not change moved out of its loop.
    ui_StageVectorize:       string = "Vectorized"                  // After neighbouring operations became one wide instruction.
    ui_StageDce:             string = "Dead code removed"           // After instructions nothing reads were dropped.
    ui_StageBeforeRegisters: string = "Before registers"            // Last form still written in unlimited virtual registers.
    ui_StageRegalloc:        string = "Registers allocated"         // After every value took a machine register or a stack slot.
    ui_StagePeephole:        string = "Peephole applied"            // After the final local rewrites over real registers.
    ui_StageFinal:           string = "Final"                       // The instruction list handed to the encoder.
}

private const FrenchStringsName = "lang/fr/prism.tweak"
private const FrenchStrings     = #include("../datas/lang/fr/prism.tweak")

private var g_AppStrings: AppStrings

// Returns the visible strings of Swag Prism in the active language.
func appStrings()->const *AppStrings => &g_AppStrings

// Registers the Swag Prism string table and its embedded translations.
//
// The resource is published before the table is registered: [[Gui.registerStrings]] translates a
// table only after it can find that table's translation file.
func registerAppStrings(bundle: *Core.Resources.Bundle)
{
    bundle.addEmbedded(FrenchStringsName, FrenchStrings)

    // The file name here becomes `lang/<tag>/prism.tweak`, which must be the exact resource name
    // published above: a mismatch does not fail, it silently shows English.
    Gui.registerStrings'AppStrings(&g_AppStrings, "prism")
}
