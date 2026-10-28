#global public

using Core, Gui

// Visible strings of Swag Prism.
//
// The name of the application is a proper name, and the name a compiler stage is spelled with is
// what the reader types into the attribute, so neither is translated.
struct AppStrings
{
    // The examples, the viewers and what a viewer says before it has run.
    ui_Examples:      string = "Examples"                             // Menu of the source examples.
    ui_Plasma:        string = "Plasma waves"                         // Name of the animated plasma example.
    ui_Julia:         string = "Julia fractal"                        // Name of the animated Julia-set example.
    ui_GuiExample:    string = "Live interface"                       // Name of the interactive control example.
    ui_Dot:           string = "Dot product"                          // Name of the optimization example.
    ui_Microcode:     string = "Microcode"                            // Name of the instruction-listing viewer.
    ui_Render2D:      string = "2D render"                            // Name of the native pixel renderer.
    ui_Gui:           string = "GUI"                                  // Name of the native GUI preview.
    ui_RenderHint:    string = "shade(x, y, time: f32)->u32"          // Function contract shown in an empty 2D viewer.
    ui_GuiHint:       string = "buildView(parent: *Gui.Wnd)"          // Function contract shown in an empty GUI viewer.
    ui_ChooseExample: string = "Choose an example, then compile."     // Help for an empty execution viewer.

    // The header of a column of results and its menus.
    ui_ViewerType:      string = "Viewer type"                  // Tooltip of the menu of the viewer a column shows.
    ui_Stage:           string = "Stage"                        // Tooltip of the stage menu, and the reading of the stage.
    ui_Optimize:        string = "Optimization level"           // Tooltip of the optimization menu, and its reading.
    ui_BuildPreset:     string = "Build preset"                 // Tooltip of the menu of the configuration a build starts from.
    ui_Pause:           string = "Pause"                        // Pauses consumption of preview frames.
    ui_Resume:          string = "Resume"                       // Resumes the paused preview.
    ui_CloseBuild:      string = "Close"                        // Closes the build configuration and shows the viewer again.
    ui_BuildHeading:    string = "Build"                        // Heads a column showing its build configuration.
    ui_InstructionOne:  string = "instruction"                  // Unit of a count of one instruction.
    ui_InstructionMany: string = "instructions"                 // Unit of a count of instructions.
    ui_SincePrevious:   string = "Since the previous stage"     // Label of the readings of a step, stage by stage.
    ui_Removed:         string = "% removed"                    // Instructions a step removed.
    ui_Added:           string = "% added"                      // Instructions a step added.
    ui_LoopNote:        string = "The loop goes from % to % instructions."     // The innermost loop of two compared builds.

    // The reading at the foot of the window, and the sheet.
    ui_Working:        string = "Compiling…"                               // While the compiler runs.
    ui_RunningViewers: string = "% viewers compiling"                      // With the number of running viewer jobs.
    ui_Done:           string = "Compiled in % ms"                         // After a compilation, with how long the compiler took.
    ui_ReusedBuild:    string = "Reused compilation (% ms)"                // Reuses the measured result of an existing compilation.
    ui_NoOutput:       string = "No output for this stage."                // When the compilation printed nothing for the stage.
    ui_Stopped:        string = "Compilation stopped."                     // When the compilation failed.
    ui_LiveStats:      string = "Build % ms | Frame % µs"                  // Measured compilation milliseconds and rendering microseconds.
    ui_ReusedStats:    string = "Reused build | Frame % µs"                // A reused native artifact and current rendering time.
    ui_Formatting:     string = "Formatting…"                              // While the formatter runs.
    ui_Formatted:      string = "Source formatted."                        // After successful formatting.
    ui_FormatFailed:   string = "Formatting failed. Source unchanged."     // When formatting cannot complete.
    ui_FormatChanged:  string = "Source changed. Format again."            // A newer edit takes precedence over a formatted snapshot.
    ui_Build:          string = "Build"                                    // Reading of the sheet: how the latest build went.
    ui_FrameSize:      string = "Frame"                                    // Reading of the sheet: the size of the frame of a preview.
    ui_Compiler:       string = "Compiler"                                 // Section of the sheet: what the compiler reported.
    ui_Formatter:      string = "Formatter"                                // Section of the sheet: what the formatter did.
    ui_LeftColumn:     string = "left"                                     // Names the left build in a section of the lens.
    ui_RightColumn:    string = "right"                                    // Names the right build in a section of the lens.
    ui_CaretPlace:     string = "Ln %, Col %"                              // Where the caret is in the source: its line, then its column.

    // What the empty listing says before anything has been compiled into it.
    //
    // The listing never wraps — an instruction listing is a set of aligned columns — so this
    // sentence has to be short enough to sit in it at the narrowest width rather than trail off.
    ui_OutputHint: string = "Compile to see the instructions."

    // Commands, as the lens names them.
    cmd_Compile:            string = "Compile"
    cmd_FormatSource:       string = "Format Source"
    cmd_LiveEdit:           string = "Recompile After Editing"
    cmd_ShowColumns:        string = "Source and Result"
    cmd_ShowStages:         string = "Stage by Stage"
    cmd_ShowCompare:        string = "Compare Two Builds"
    cmd_Information:        string = "Information"
    cmd_PreviousStage:      string = "Previous Stage"
    cmd_NextStage:          string = "Next Stage"
    cmd_ShowChange:         string = "Show the Change"
    cmd_ShowSourceLines:    string = "Show Source Lines"
    cmd_ShowOpcodes:        string = "Show Opcodes"
    cmd_CopyListing:        string = "Copy Listing"
    cmd_BuildConfiguration: string = "Build Configuration"
    cmd_RestoreBuild:       string = "Restore Defaults"
    cmd_PausePreview:       string = "Pause Preview"
    cmd_ResumePreview:      string = "Resume Preview"

    // Sections of the lens.
    lens_Source:       string = "Source"
    lens_View:         string = "View"
    lens_Build:        string = "Build"
    lens_Examples:     string = "Examples"
    lens_ViewAs:       string = "View As"
    lens_Stage:        string = "Stage"
    lens_Optimization: string = "Optimization"
    lens_Preset:       string = "Build Preset"

    // The hint line: keys, in their keycaps, and what they do.
    key_Compile:  string = "Ctrl ⏎"                           // The key that compiles.
    key_Lens:     string = "Ctrl K"                           // The key that opens the lens where Space types.
    key_Steps:    string = "← →"                              // The keys that step through the stages.
    hint_Compile: string = "compile"                          // What the compile key does.
    hint_Lens:    string = "views, stages, examples"          // What the lens holds.
    hint_Steps:   string = "previous, next stage · % / %"     // What the arrows do, with the place of the step.

    // What a compilation or a preview reports when it stops without compiler output of its own.
    msg_BuildTimeout:   string = "Compilation exceeded 60 seconds."      // The compiler ran past the watchdog.
    msg_BuildFailed:    string = "The compiler could not complete the build."     // The compiler process could not finish.
    msg_FormatTimeout:  string = "Formatting exceeded 60 seconds."       // The formatter ran past the watchdog.
    msg_PreviewNotRun:  string = "The preview could not be started."     // The preview process could not be launched.
    msg_PreviewStalled: string = "The preview did not produce a frame for 10 seconds."     // The running preview stopped drawing.
    msg_PreviewExited:  string = "The preview exited with code %."       // The preview process ended on its own, with its exit code.

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
