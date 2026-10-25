namespace Swag
{
    // #########################################################
    // Targets and commands
    // #########################################################

    #[EnumFlags]
    enum RuntimeFlags: u64
    {
        Zero         = 0
        FromCompiler = 1
    }

    // Target processor
    enum TargetArch { X86_64 }

    // The 'OS' to target when generating native code
    enum TargetOs
    {
        Windows     // Windows
    }

    // The compiler command being executed.
    enum CompilerCommand
    {
        Test
        Format
        Build
    }

    // #########################################################
    // Compiler
    // #########################################################

    // The kind of message in [[CompilerMessage]]
    enum CompilerMsgKind: u32
    {
        PassAfterSemantic         // Called once the program semantic has been done
        PassBeforeRunByteCode     // Called just before running bytecode
        PassBeforeOutput          // Called just before generating the native code
        PassAllDone               // Called when everything has been done
        SemFunctions              // Called for each function in the module
        SemTypes                  // Called for each type in the module
        SemGlobals                // Called for each global variable in the module
        AttributeGen
    }

    // The type of message you want to retrieve in a '#message' function.
    //
    // The function could be called for more than one reason, as this is a mask.
    #[EnumFlags]
    enum CompilerMsgMask: u64
    {
        PassAfterSemantic = 1 << cast(u32, CompilerMsgKind.PassAfterSemantic)
        PassBeforeRun     = 1 << cast(u32, CompilerMsgKind.PassBeforeRunByteCode)
        PassBeforeOutput  = 1 << cast(u32, CompilerMsgKind.PassBeforeOutput)
        PassAllDone       = 1 << cast(u32, CompilerMsgKind.PassAllDone)
        SemFunctions      = 1 << cast(u32, CompilerMsgKind.SemFunctions)
        SemTypes          = 1 << cast(u32, CompilerMsgKind.SemTypes)
        SemGlobals        = 1 << cast(u32, CompilerMsgKind.SemGlobals)
        AttributeGen      = 1 << cast(u32, CompilerMsgKind.AttributeGen)
        All               = 0xFFFFFFFF_FFFFFFFF
    }

    // A message received in a '#message' function.
    //
    // In a '#message' function, retrieve the associated message by calling 'getMessage' on the
    // interface returned by [[Swag.compiler]].
    struct CompilerMessage
    {
        public
        {
            moduleName: string?              // Name of the module for which the message is sent.
            name:       string?              // Depends on 'kind'
            type:       const *TypeInfo?     // Depends on 'kind'
            kind:       CompilerMsgKind      // Kind of the message
        }
    }

    // This is the interface to communicate with the compiler.
    //
    // The intrinsic 'Swag.compiler()' will return that interface at compile-time, and 'null' at runtime.
    interface ICompiler
    {
        mtd getMessage()->const *CompilerMessage?     // Returns the compiler message in a '#message' function
        mtd getBuildCfg()->*Build.Config?             // Returns the build configuration of the current module
        mtd compileString(str: string)
    }
}

// The build configuration of a module, as [[Swag.ICompiler.getBuildCfg]] returns it.
namespace Swag.Build
{
    // #########################################################
    // Build configuration
    // #########################################################

    // Controls which calls the semantic inliner expands.
    enum BackendInlineMode: u8
    {
        Never      = 0     // Only mandatory expansions (macro/mixin); no inlining.
        MarkedOnly = 1     // Also inline functions explicitly tagged #[Inline].
        Auto       = 2     // MarkedOnly plus compiler-chosen small/cheap callees.
    }

    // How much of the backend optimizer a build asks for.
    enum BackendOptimLevel: u8
    {
        O0 = 0     // No backend optimization.
        O1 = 1     // Everything that does not cost compilation time; the 'devmode' preset.
        O2 = 2     // Also what does; the 'release' preset.
    }

    // Iterations policy overrides; every zero field selects the compiler default.
    struct OptimizerIterations
    {
        public
        {
            preRaSweeps:             u32     // Pre-allocation optimization sweeps; exhaustion reports a compiler error. Zero selects 1 at O0, otherwise 24.
            allocationSweeps:        u32     // Legalization/allocation sweeps; exhaustion reports a compiler error. Zero selects 16.
            postRaSweeps:            u32     // Post-allocation cleanup sweeps; exhaustion keeps the last valid result. Zero selects 1 at O0, otherwise 24.
            prePrologueSweeps:       u32     // Peephole and dead-code cleanup sweeps before frame setup. Zero selects 2.
            branchThreadRounds:      u32     // Branch-threading rounds within one pass invocation. Zero selects 4096.
            inductionVariableRounds: u32     // Loop rediscovery rounds within one induction-variable pass. Zero selects 32.
            loopInvariantRounds:     u32     // Hoisting rounds within one loop-invariant-code-motion pass. Zero selects 64.
            sinkToUseRounds:         u32     // Scheduling rounds that move definitions towards their consumers. Zero selects 4.
            registerJoinRounds:      u32     // Copy-coalescing rounds before register allocation. Zero selects 4.
            postRaHoistLevels:       u32     // Outer-loop levels visited by post-allocation hoisting. Zero selects 3.
        }
    }

    // Unroll policy overrides; every zero field selects the compiler default.
    struct OptimizerUnroll
    {
        public
        {
            memoryBytes:                  u32     // Maximum bytes expanded for constant-size memory operations. Zero selects 256.
            maxTrips:                     u32     // Maximum trip count for ordinary full loop unrolling. Zero selects 16.
            maxWideTableTrips:            u32     // Maximum trip count admitting larger constant-table bodies. Zero selects 4.
            maxBodyInstructions:          u32     // Maximum original instructions considered for full unrolling; ordinary loops also obey their own cap. Zero selects 144.
            maxTotalInstructions:         u32     // Maximum expanded instructions for the constant-table exception. Zero selects 576.
            maxOrdinaryBodyInstructions:  u32     // Maximum original instructions for ordinary full unrolling. Zero selects 96.
            maxOrdinaryTotalInstructions: u32     // Maximum expanded instructions for ordinary full unrolling. Zero selects 384.
            maxBranchedTotalInstructions: u32     // Maximum expanded instructions when branches survive unrolling. Zero selects 96.
            maxNestedTotalInstructions:   u32     // Maximum flattened instructions for a fully unrolled loop nest. Zero selects 768.
            maxPartialBodyInstructions:   u32     // Maximum original instructions for partial indexed-loop unrolling. Zero selects 12.
            partialFactor:                u32     // Scalar copies per partial indexed-loop iteration; clamped to 1..64. Zero selects 4.
            initializerLookback:          u32     // Maximum preheader instructions searched for the loop counter initializer. Zero selects 8.
            sumInitializerLookback:       u32     // Maximum preheader instructions searched for an accumulator initializer. Zero selects 16.
        }
    }

    // Vectorization policy overrides; every zero field selects the compiler default.
    struct OptimizerVectorization
    {
        public
        {
            maxPlanInstructions: u32     // Maximum generated instructions in one SLP vectorization plan. Zero selects 4096.
            maxTreeDepth:        u32     // Maximum recursive SLP tree depth; capped at the implementation stack bound of 512. Zero selects 512.
            maxPromotedPerLoop:  u32     // Maximum vector-state objects promoted simultaneously in one loop. Zero selects 6.
        }
    }

    // Backend optimization budgets for this compilation.
    //
    // Zero fields retain the compiler defaults. Set overrides during module setup; the optimizer
    // copies the resulting configuration for each function. These budgets do not enable passes
    // disabled by [[Swag.Build.Backend.optimLevel]] or [[Swag.Build.Backend.vectorize]]. Fixed proof limits
    // and instruction representations remain compiler-owned.
    //
    // ```swag
    // #run
    // {
    //     let cfg = unwrap Swag.compiler().getBuildCfg()
    //     cfg.backend.optimizer.iterations.preRaSweeps = 48
    //     cfg.backend.optimizer.unroll.maxTrips = 32
    //     cfg.backend.optimizer.unroll.memoryBytes = 512
    // }
    // ```
    struct Optimizer
    {
        public
        {
            iterations:    OptimizerIterations        // Budgets for pipeline sweeps and local pass rounds.
            unroll:        OptimizerUnroll            // Code-growth and discovery budgets for loops and memory operations.
            vectorization: OptimizerVectorization     // Budgets for vector-plan discovery and loop promotion.
        }
    }

    // Floating-point policy for this compilation.
    //
    // The release preset enables 'fma', 'noNaN', 'noInf', and 'noSignedZero'. The devmode
    // preset leaves all fields false. 'unsafe' and 'approxFunc' reserve permissions for
    // future optimizations and currently have no effect. These flags do not enable optimizer
    // passes disabled by [[Swag.Build.Backend.optimLevel]].
    struct BackendMath
    {
        public
        {
            fma:          bool     // Allow contraction into fused multiply-add instructions, which round once instead of twice.
            noNaN:        bool     // Assume floating-point values are not NaN.
            noInf:        bool     // Assume floating-point values are never infinite.
            noSignedZero: bool     // Allow transformations that ignore the sign of zero.
            unsafe:       bool     // Reserved permission for unsafe floating-point transformations; currently unused.
            approxFunc:   bool     // Reserved permission for approximate math-function implementations; currently unused.
        }
    }

    // Backend options
    struct Backend
    {
        public
        {
            optimLevel       = BackendOptimLevel.O0             // Backend optimization level (set per build config)
            vectorize: bool                                     // Auto-vectorize; true in 'release'
            debugInfo        = false                            // Emit native debug information (CodeView and PDB on Windows); '--debug' enables it for command-line builds
            enableExceptions = true                             // Generate unwind information for JIT code and register it with the host (SEH function tables on Windows)
            math:      BackendMath                              // Floating-point assumptions and transformation permissions.
            inlineMode       = BackendInlineMode.MarkedOnly     // Inlining policy (set per build config)
            optimizer: Optimizer                                // Per-compilation optimization budgets; zero fields keep compiler defaults.
        }
    }

    // The kind of native backend to generate.
    enum BackendKind
    {
        None              // Nothing
        SharedLibrary     // The module needs to be compiled as a shared library.
        Executable        // The module needs to be compiled to an executable application.
        StaticLibrary     // The module needs to be compiled as a static library.
        Export            // The module only exports dependency metadata/API and does not produce a native artifact.
    }

    // The native backend sub category.
    //
    // Whether an executable is a windowed or a console application.
    //
    // Windows builds a windowed application by default; 'Console' attaches it to a console instead.
    // Hosts that do not distinguish the two ignore it.
    enum BackendSubKind
    {
        Default
        Console
    }

    enum DocKind
    {
        None         // Do not generate documentation for that module
        Api          // Generate 'api like' documentation
        Examples     // Generate 'examples like' documentation
        Pages        // Generate one page per file
    }

    // How a generated documentation page picks between its light and dark palettes.
    enum DocTheme
    {
        Auto      // Follow the reader's system preference
        Light     // Always render the light palette
        Dark      // Always render the dark palette
    }

    // This contains all options when generating documentation.
    struct GenDoc
    {
        public
        {
            kind                     = DocKind.None      // The kind of documentation to generate
            outputName:          string?                 // The name of the HTML output file (without extension)
            titleToc:            string?                 // Title for the table of content
            titleContent:        string?                 // Title for the main document content
            css:                 string?                 // Relative output path of the generated stylesheet
            icon:                string?                 // The icon path of the page
            morePages:           string?                 // Additional external file pages to process (separated with ';')
            quoteIconNote:       string?                 // The icon for the note blockquote
            quoteIconTip:        string?                 // The icon for the tip blockquote
            quoteIconWarning:    string?                 // The icon for the warning blockquote
            quoteIconAttention:  string?                 // The icon for the attention blockquote
            quoteIconExample:    string?                 // The icon for the example blockquote
            quoteTitleNote:      string?                 // The title for the note blockquote
            quoteTitleTip:       string?                 // The title for the tip blockquote
            quoteTitleWarning:   string?                 // The title for the warning blockquote
            quoteTitleAttention: string?                 // The title for the attention blockquote
            quoteTitleExample:   string?                 // The title for the example blockquote
            brandName:           string?                 // The wordmark shown at the left of the page header
            brandUrl:            string?                 // The page the wordmark links to
            navLinks:            string?                 // Header navigation, as 'Label=Url' entries separated with ';'
            footer:              string?                 // Extra text placed in the page footer
            syntaxDefaultColor:  u32 = 0x00222222        // Code syntax default color (if not colorized)
            syntaxColorLum:      f32 = 0.5               // Code syntax color luminosity in range ]0, 1]
            accentColor:         u32 = 0                 // Accent color of the pages, as 0xRRGGBB; 0 keeps the swag accent
            theme                    = DocTheme.Auto     // Which palette the generated pages use
            hasSwagWatermark         = true              // Generate a swag watermark at the bottom of each page
            hasSymbolIndex           = true              // List every documented symbol in the sidebar of an 'api like' page
            hasSearch                = true              // Add a search box, and the index of the page it searches
        }
    }

    // How a module reports its warnings.
    //
    // Each field lists warning identifiers separated with `|`, and accepts `"all"` to name
    // every warning at once. A field that names a warning outranks a field that says `"all"`,
    // whichever field it is, and every field here is outranked by [[Warning]] written on a
    // declaration, a block, or a file.
    // ```swag
    // #run
    // {
    //     let cfg = unwrap Swag.compiler().getBuildCfg()
    //     cfg.warnings.asErrors = "all"
    //     cfg.warnings.disabled = "sema_warn_unreachable_code"
    // }
    // ```
    struct Warnings
    {
        public
        {
            asErrors:   string?     // Warnings reported as errors
            asWarnings: string?     // Warnings reported as warnings
            disabled:   string?     // Warnings not reported at all
        }
    }

    // The current module build configuration.
    //
    // See [[ICompiler]]. Allocator diagnostic fields exist only with compiler tag
    // 'Swag.AllocatorDiagnostics', selected before module setup.
    struct Config
    {
        public
        {
            moduleVersion:   u32 = 0         // The module version
            moduleRevision:  u32 = 0         // The module revision
            moduleBuildNum:  u32 = 0         // The module build value
            moduleNamespace: string?         // The namespace name of the module
            embeddedImports      = false     // Module should embed all its dependencies
            ignoreInWorkspace    = false     // Skip this module when building a workspace
            publishDependencies  = false     // Place the shared libraries an executable needs beside it, so it runs without the compiler

            tempAllocatorCapacity  = 4'u32 * 1024 * 1024     // Default capacity of the 'temp' allocator (in bytes)
            errorAllocatorCapacity = 16'u32 * 1024           // Default capacity of the 'error' allocator (in bytes)
            safetyGuards           = SafetyWhat.All          // Activate language RUNTIME safety checks; allocator checks use the early 'Swag.AllocatorSafety' tag
            sanityGuards           = SafetyWhat.All          // Activate specific STATIC (compile-time) sanity checks
        }

        #static if #hastag("Swag.AllocatorDiagnostics")
        {
            public
            {
                allocatorCaptureStack     = false     // Capture a call stack for each tracked allocation
                allocatorLeaks            = true      // Report memory leaks at runtime shutdown
                allocatorTrackAllocations = false     // Keep an exact allocation list for detailed leak reporting
                allocatorElectricMode     = false     // Never reuse freed blocks
                allocatorFillMemory       = false     // Fill allocated/freed memory with debug patterns
            }
        }
        else
        {
            // The compiler interface keeps the same layout with either public surface.
            private reservedAllocatorDiagnostics: [5] u8
        }

        public
        {
            errorStackTrace = true     // Add stack trace in case a 'fail' is raised

            warnings: Warnings     // How this module reports its warnings

            backendKind    = BackendKind.Executable     // Backend type (executable, shared library, static library, export...)
            backendSubKind = BackendSubKind.Console     // Backend sub kind

            name:    string?     // Artifact name
            outDir:  string?     // Artifact output directory
            workDir: string?     // Work directory

            backend: Backend     // Backend options

            repoPath:          string?     // Repository access path to the module
            resAppIcoFileName: string?     // For an executable, the associated icon file name, embedded as a resource on Windows. Relative paths start at the module folder.
            resAppName:        string?     // For an executable, the associated application name
            resAppDescription: string?     // For an executable, the associated application description
            resAppCompany:     string?     // For an executable, the associated company name
            resAppCopyright:   string?     // For an executable, the associated copyright notice
            genDoc:            GenDoc      // Parameters for document generation
            registeredConfigs: string = "devmode|release"     // Registered build configuration names used by --build-cfg and #cfg
        }
    }
}
