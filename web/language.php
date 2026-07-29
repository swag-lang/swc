<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta http-equiv="X-UA-Compatible" content="IE=edge">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<?php include('common/start-head.php'); ?><title>Swag Language Reference</title>
<link rel="icon" type="image/x-icon" href="favicon.ico">
<link rel="stylesheet" type="text/css" href="css/style.css">
<script src="https://kit.fontawesome.com/f76be2b3ee.js" crossorigin="anonymous"></script>
<style>
.container{display:flex;flex-wrap:nowrap;flex-direction:row;margin:0 auto;padding:0}.left{display:block;overflow-y:auto;width:500px}.left-page{margin:10px}.right{display:block;width:100%}.right-page{max-width:1024px;margin:10px auto}
@media(min-width:640px){.container{max-width:640px}}@media(min-width:768px){.container{max-width:768px}}@media(min-width:1024px){.container{max-width:1024px}}@media(min-width:1280px){.container{max-width:1280px}}@media(min-width:1536px){.container{max-width:1536px}}@media screen and (max-width:600px){.left{display:none}.right-page{margin:10px}}
html{font-family:ui-sans-serif,system-ui,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif}body{margin:0;line-height:1.3em}.container a{color:DodgerBlue}.container a:hover{text-decoration:underline}.container img{margin:0 auto}.left a{text-decoration:none}.left ul{list-style-type:none;margin-left:-20px}.left h3{background-color:#000;color:#fff;padding:6px}.right h1{margin-top:50px;margin-bottom:50px}.right h2{margin-top:35px}.right hr{margin-top:50px;margin-bottom:50px}.strikethrough-text{text-decoration:line-through}.swag-watermark{text-align:right;font-size:80%;margin-top:30px}.swag-watermark a{text-decoration:none;color:inherit}
.blockquote{border-radius:5px;border:1px solid;margin:20px;padding:10px}.blockquote-default{border-color:orange;border-left:6px solid orange;background-color:#ffffe0}.blockquote-note{border-color:#adcedd;background-color:#cdeefd}.blockquote-tip{border-color:#bccfbc;background-color:#dcefdc}.blockquote-warning{border-color:#dfbdb3;background-color:#ffddd3}.blockquote-attention{border-color:#ddbab8;background-color:#fddad8}.blockquote-example{border:2px solid #d3d3d3}.blockquote-title-block{margin-bottom:10px}.blockquote-title{font-weight:bold}.description-list-title{font-weight:bold;font-style:italic}.description-list-block{margin-left:30px}
.container table{border:1px solid #d3d3d3;border-collapse:collapse;font-size:90%;margin:20px}.container td,.container th{border:1px solid #d3d3d3;padding:6px;min-width:100px}.container th{background-color:#eee}table.api-item{border-collapse:separate;background-color:#000;color:#fff;width:100%;margin:70px 0 0;font-size:110%}.api-item td{font-size:revert;border:0}.api-item td:first-child{width:66%;white-space:nowrap}.api-item-title-src-ref{text-align:right}.api-item-title-src-ref a{color:inherit}.api-item-title-kind{font-weight:normal;font-size:80%}.api-item-title-strong{font-weight:bold}.table-enumeration{width:calc(100% - 40px)}.table-enumeration td:first-child{background-color:#f8f8f8;white-space:nowrap}.table-enumeration td:last-child{width:100%}.table-enumeration td.code-type{background-color:#eee}.table-enumeration a{text-decoration:none;color:inherit}
.code-inline{background-color:#eee;border-radius:5px;border:1px dotted #ccc;padding:0 8px;font-size:110%;font-family:monospace;display:inline-block}.code-block{background-color:#eee;border-radius:5px;border:1px solid #d3d3d3;padding:10px;margin:20px;white-space:pre;overflow-x:auto;font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,"Liberation Mono",monospace}.code-block a{color:inherit}
.SCmt{color:#6a9955}.SCmp,.SAtr{color:#777}.SFct{color:#c54f00}.SCst{color:#168f7d}.SItr{color:#8a7600}.STpe{color:#a66c00}.SKwd{color:#286fa8}.SLgc{color:#8e4d99}.SNum{color:#4d7a45}.SStr{color:#a64f38}.SInv{color:#d22}.SBcR{color:#817c31}
.SCde{color:#222222}
.container{height:100vh}.right{overflow-y:auto}
</style>
<?php include('common/end-head.php'); ?>
</head>
<body>
<?php include('common/start-body.php'); ?>
<div class="container">
<div class="left"><div class="left-page">
<h2>Table of Contents</h2>
<ul>
<li><a href="#_001_000_introduction_swg">Introduction</a></li>
<ul>
<li><a href="#_001_001_using_this_reference_swg">Using This Reference</a></li>
<li><a href="#_001_002_language_tour_swg">Language Tour</a></li>
<li><a href="#_001_003_hello_world_and_beyond_swg">Hello World and Beyond</a></li>
<li><a href="#_001_004_swc_command_line_swg">Swc Command Line</a></li>
</ul>
<li><a href="#_002_000_modules_and_source_code_swg">Modules and Source Code</a></li>
<ul>
<li><a href="#_002_001_workspaces_modules_and_dependencies_swg">Workspaces Modules and Dependencies</a></li>
<li><a href="#_002_002_source_files_swg">Source Files</a></li>
<li><a href="#_002_003_global_declaration_order_swg">Global Declaration Order</a></li>
<li><a href="#_002_004_comments_swg">Comments</a></li>
<li><a href="#_002_005_semicolons_swg">Semicolons</a></li>
<li><a href="#_002_006_identifiers_swg">Identifiers</a></li>
<li><a href="#_002_007_keywords_swg">Keywords</a></li>
<li><a href="#_002_008_sigils_swg">Sigils</a></li>
<li><a href="#_002_009_visibility_and_exports_swg">Visibility and Exports</a></li>
<li><a href="#_002_010_module_lifecycle_swg">Module Lifecycle</a></li>
</ul>
<li><a href="#_003_000_fundamentals_swg">Fundamentals</a></li>
<ul>
<li><a href="#_003_001_basic_types_swg">Basic Types</a></li>
<li><a href="#_003_002_number_literals_swg">Number Literals</a></li>
<li><a href="#_003_003_string_swg">String</a></li>
<li><a href="#_003_004_constants_swg">Constants</a></li>
<li><a href="#_003_005_variables_swg">Variables</a></li>
<li><a href="#_003_006_operators_swg">Operators</a></li>
<li><a href="#_003_007_cast_swg">Cast</a></li>
<li><a href="#_003_008_alias_swg">Alias</a></li>
</ul>
<li><a href="#_004_000_data_structures_swg">Data Structures</a></li>
<ul>
<li><a href="#_004_001_array_swg">Array</a></li>
<li><a href="#_004_002_slice_swg">Slice</a></li>
<li><a href="#_004_003_tuple_swg">Tuple</a></li>
<li><a href="#_004_004_enum_swg">Enum</a></li>
<li><a href="#_004_005_impl_swg">Impl</a></li>
<li><a href="#_004_006_union_swg">Union</a></li>
<li><a href="#_004_007_pointers_swg">Pointers</a></li>
<li><a href="#_004_008_references_swg">References</a></li>
<li><a href="#_004_009_any_swg">Any</a></li>
</ul>
<li><a href="#_005_000_control_flow_swg">Control Flow</a></li>
<ul>
<li><a href="#_005_001_if_swg">If</a></li>
<li><a href="#_005_002_for_swg">For</a></li>
<li><a href="#_005_003_for_elements_swg">For Elements</a></li>
<li><a href="#_005_004_while_swg">While</a></li>
<li><a href="#_005_005_switch_swg">Switch</a></li>
<li><a href="#_005_006_break_swg">Break</a></li>
</ul>
<li><a href="#_006_000_structs_swg">Structs</a></li>
<ul>
<li><a href="#_006_001_declaration_swg">Declaration</a></li>
<li><a href="#_006_002_impl_swg">Impl</a></li>
<li><a href="#_006_003_offset_swg">Offset</a></li>
<li><a href="#_006_004_packing_swg">Packing</a></li>
<li><a href="#_006_005_operator_overloading_swg">Operator Overloading</a></li>
<li><a href="#_006_006_custom_assignment_swg">Custom Assignment</a></li>
<li><a href="#_006_007_custom_loop_swg">Custom Loop</a></li>
<li><a href="#_006_008_custom_iteration_swg">Custom Iteration</a></li>
<li><a href="#_006_009_custom_copy_and_move_swg">Custom Copy and Move</a></li>
<li><a href="#_006_010_custom_literals_swg">Custom Literals</a></li>
<li><a href="#_006_011_interface_swg">Interface</a></li>
</ul>
<li><a href="#_007_000_functions_swg">Functions</a></li>
<ul>
<li><a href="#_007_001_declaration_swg">Declaration</a></li>
<li><a href="#_007_002_lambda_swg">Lambda</a></li>
<li><a href="#_007_003_closure_swg">Closure</a></li>
<li><a href="#_007_004_variadic_parameters_swg">Variadic Parameters</a></li>
<li><a href="#_007_005_function_overloading_swg">Function Overloading</a></li>
<li><a href="#_007_006_ufcs_swg">Ufcs</a></li>
<li><a href="#_007_007_discard_swg">Discard</a></li>
<li><a href="#_007_008_retval_swg">Retval</a></li>
</ul>
<li><a href="#_008_000_intrinsics_swg">Intrinsics</a></li>
<ul>
<li><a href="#_008_001_init_swg">Init</a></li>
<li><a href="#_008_002_drop_swg">Drop</a></li>
<li><a href="#_008_003_value_and_type_intrinsics_swg">Value and Type Intrinsics</a></li>
<li><a href="#_008_004_math_and_bit_intrinsics_swg">Math and Bit Intrinsics</a></li>
<li><a href="#_008_005_memory_and_atomic_intrinsics_swg">Memory and Atomic Intrinsics</a></li>
</ul>
<li><a href="#_009_000_generics_swg">Generics</a></li>
<ul>
<li><a href="#_009_001_functions_swg">Functions</a></li>
<li><a href="#_009_002_structs_swg">Structs</a></li>
<li><a href="#_009_003_where_constraints_swg">Where Constraints</a></li>
</ul>
<li><a href="#_010_000_attributes_swg">Attributes</a></li>
<ul>
<li><a href="#_010_001_user_attributes_swg">User Attributes</a></li>
<li><a href="#_010_002_predefined_attributes_swg">Predefined Attributes</a></li>
</ul>
<li><a href="#_011_000_scoping_swg">Scoping</a></li>
<ul>
<li><a href="#_011_001_namespace_swg">Namespace</a></li>
<li><a href="#_011_002_defer_swg">Defer</a></li>
<li><a href="#_011_003_using_swg">Using</a></li>
<li><a href="#_011_004_with_swg">With</a></li>
</ul>
<li><a href="#_012_000_type_reflection_swg">Type Reflection</a></li>
<ul>
<li><a href="#_012_001_aggregate_reflection_swg">Aggregate Reflection</a></li>
<li><a href="#_012_002_function_and_container_reflection_swg">Function and Container Reflection</a></li>
</ul>
<li><a href="#_013_000_error_management_and_safety_swg">Error Management and Safety</a></li>
<ul>
<li><a href="#_013_001_error_management_swg">Error Management</a></li>
<li><a href="#_013_002_safety_swg">Safety</a></li>
<li><a href="#_013_003_sanity_swg">Sanity</a></li>
</ul>
<li><a href="#_014_000_compile-time_evaluation_swg">Compile-time Evaluation</a></li>
<ul>
<li><a href="#_014_001_constexpr_swg">Constexpr</a></li>
<li><a href="#_014_002_run_swg">Run</a></li>
<li><a href="#_014_003_compiler_instructions_swg">Compiler Instructions</a></li>
<li><a href="#_014_004_code_inspection_swg">Code Inspection</a></li>
</ul>
<li><a href="#_015_000_metaprogramming_swg">Metaprogramming</a></li>
<ul>
<li><a href="#_015_001_mixins_swg">Mixins</a></li>
<li><a href="#_015_002_macros_swg">Macros</a></li>
<li><a href="#_015_003_generated_code_with_ast_swg">Generated Code with Ast</a></li>
<li><a href="#_015_004_compiler_interface_swg">Compiler Interface</a></li>
</ul>
<li><a href="#_016_000_interoperability_swg">Interoperability</a></li>
<ul>
<li><a href="#_016_001_foreign_functions_swg">Foreign Functions</a></li>
<li><a href="#_016_002_c_abi_data_swg">C Abi Data</a></li>
</ul>
</ul>
</div></div>
<div class="right"><div class="right-page">
<h1>Swag Language Reference</h1>
<h2 id="_001_000_introduction_swg">Introduction</h2>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>
</span></div>
<p>Start here if Swag is new to you. This chapter explains how to run the reference with <span class="code-inline">swc</span>, gives an executable tour of the language, and grows a minimal program from <span class="code-inline">#main</span> into compile-time code.</p>
<p>The examples assume basic programming knowledge but no prior Swag experience.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_001_001_using_this_reference_swg">Using This Reference</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>
</span></div>
<p>This reference teaches Swag through small, executable examples. The compiler builds every <span class="code-inline">.swg</span> file in this module and runs each <span class="code-inline">#test</span> block, so the code beside the explanations is also the documentation's regression suite.</p>
<h3 id="What_This_Reference_Covers">What This Reference Covers</h3>
<p>The chapters progress from source organization and built-in types to control flow, user-defined types, functions, generics, reflection, safety, compile-time execution, metaprogramming, and foreign interoperability.</p>
<p>The reference focuses on the <b>language and compiler runtime</b>. Containers, filesystem access, text formatting, threading, and other library facilities live under <span class="code-inline">bin/std/modules</span> and are outside this module's scope.</p>
<h3 id="Running_the_Examples">Running the Examples</h3>
<p>From a repository checkout, test only this module with:</p>
<div class="code-block"><span class="SCde">swc test --workspace &lt;repository-root&gt;/bin/reference --workspace-module language
</span></div>
<p>The shorter forms are equivalent:</p>
<div class="code-block"><span class="SCde">swc test -w &lt;repository-root&gt;/bin/reference -m language
</span></div>
<p>Run the command without '-m language' to test every module in the reference workspace. The <span class="code-inline">test</span> command uses the <span class="code-inline">fast-debug</span> build configuration by default; select another registered configuration with <span class="code-inline">--build-cfg</span> (or <span class="code-inline">-bc</span>):</p>
<div class="code-block"><span class="SCde">swc test -w &lt;repository-root&gt;/bin/reference -m language -bc debug
</span></div>
<h3 id="How_to_Read_the_Examples">How to Read the Examples</h3>
<ul>
<li>A <span class="code-inline">#test</span> block runs only for the <span class="code-inline">test</span> command.</li>
<li><span class="code-inline">#assert</span> checks a condition while compiling.</li>
<li><span class="code-inline">@assert</span> checks a condition while the generated program runs.</li>
<li>Deliberately invalid examples stay commented out and explain the diagnostic</li>
</ul>
<p>they are intended to produce.</p>
<ul>
<li>Most declarations are private to this module so examples do not accidentally</li>
</ul>
<p>become part of another module's API.</p>
<div class="blockquote blockquote-tip">
<div class="blockquote-title-block"><span class="blockquote-title">Tip</span></div>
<p>Copy a <span class="code-inline">#test</span> body into a function or executable while experimenting. Keep <span class="code-inline">#assert</span> for compile-time facts and <span class="code-inline">@assert</span> for runtime behavior.</p>
</div>
<h3 id="Accuracy_and_Scope">Accuracy and Scope</h3>
<p>Examples in this module deliberately avoid standard-library dependencies unless a chapter is specifically about integration. Passing tests prove that the shown syntax and runtime results agree with the compiler version that shipped them. Prose still explains constraints that cannot be expressed by a successful test, such as rejected syntax or platform-specific linking requirements.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_001_002_language_tour_swg">Language Tour</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Values_and_Mutability">Values and Mutability</h3>
<p><span class="code-inline">const</span> declares a compile-time value, <span class="code-inline">let</span> binds a runtime value once, and <span class="code-inline">var</span> declares mutable storage. Types are inferred when the initializer is unambiguous and can be written explicitly when they are part of the contract.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">const</span> <span class="SCst">MaxRetries</span> = <span class="SNum">3</span>
    <span class="SKwd">let</span> serviceName = <span class="SStr">"search"</span>
    <span class="SKwd">var</span> attempts: <span class="STpe">u32</span>

    attempts += <span class="SNum">1</span>

    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(<span class="SCst">MaxRetries</span>) == <span class="STpe">s32</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(serviceName) == <span class="STpe">string</span>)
    <span class="SItr">@assert</span>(attempts == <span class="SNum">1</span>)
}

</span></div>
<h3 id="Data_with_Behavior">Data with Behavior</h3>
<p>A <span class="code-inline">struct</span> groups fields. An <span class="code-inline">impl</span> block adds methods without changing the stored layout. In a method, <span class="code-inline">me</span> is the receiver and <span class="code-inline">.field</span> is shorthand for <span class="code-inline">me.field</span>.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">struct</span> <span class="SCst">TourPoint</span>
{
    x, y: <span class="STpe">s32</span>
}

<span class="SKwd">impl</span> <span class="SCst">TourPoint</span>
{
    <span class="SKwd">mtd</span> <span class="SFct">translate</span>(dx, dy: <span class="STpe">s32</span>)
    {
        .x += dx
        .y += dy
    }

    <span class="SKwd">mtd</span> <span class="SKwd">const</span> <span class="SFct">squaredLength</span>() =&gt; .x * .x + .y * .y
}

<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> point = <span class="SCst">TourPoint</span>{<span class="SNum">3</span>, <span class="SNum">4</span>}
    <span class="SItr">@assert</span>(point.<span class="SFct">squaredLength</span>() == <span class="SNum">25</span>)

    point.<span class="SFct">translate</span>(<span class="SNum">1</span>, -<span class="SNum">2</span>)
    <span class="SItr">@assert</span>(point.x == <span class="SNum">4</span> <span class="SLgc">and</span> point.y == <span class="SNum">2</span>)
}

</span></div>
<h3 id="Collections_and_Iteration">Collections and Iteration</h3>
<p>Arrays own a fixed number of elements. Slices are non-owning views. The same 'for value in collection' form visits both, and <span class="code-inline">[index]</span> binds the logical index when it is needed.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> values = [<span class="SNum">2</span>, <span class="SNum">4</span>, <span class="SNum">6</span>, <span class="SNum">8</span>]
    <span class="SKwd">let</span> middle = values[<span class="SNum">1</span> <span class="SLgc">until</span> <span class="SNum">3</span>]
    <span class="SKwd">var</span> total  = <span class="SNum">0</span>

    <span class="SLgc">for</span> value, [index] <span class="SLgc">in</span> middle
    {
        <span class="SItr">@assert</span>(value == values[index + <span class="SNum">1</span>])
        total += value
    }

    <span class="SItr">@assert</span>(total == <span class="SNum">10</span>)
}

</span></div>
<h3 id="Branching">Branching</h3>
<p><span class="code-inline">if</span> handles boolean conditions. <span class="code-inline">switch</span> is the natural choice when one value selects among several cases. Blocks may use braces, or <span class="code-inline">do</span> for a single statement.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">enum</span> <span class="SCst">TourState</span>
{
    <span class="SCst">Idle</span>
    <span class="SCst">Running</span>
    <span class="SCst">Failed</span>
}

<span class="SKwd">func</span> <span class="SFct">tourStateLabel</span>(state: <span class="SCst">TourState</span>)-&gt;<span class="STpe">string</span>
{
    <span class="SLgc">switch</span> state
    {
    <span class="SLgc">case</span> .<span class="SCst">Idle</span>:    <span class="SLgc">return</span> <span class="SStr">"idle"</span>
    <span class="SLgc">case</span> .<span class="SCst">Running</span>: <span class="SLgc">return</span> <span class="SStr">"running"</span>
    <span class="SLgc">case</span> .<span class="SCst">Failed</span>:  <span class="SLgc">return</span> <span class="SStr">"failed"</span>
    }

    <span class="SLgc">unreachable</span>
}

<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> state = <span class="SCst">TourState</span>.<span class="SCst">Running</span>

    <span class="SLgc">if</span> state == .<span class="SCst">Running</span> <span class="SLgc">do</span>
        <span class="SItr">@assert</span>(<span class="SFct">tourStateLabel</span>(state) == <span class="SStr">"running"</span>)
    <span class="SLgc">else</span> <span class="SLgc">do</span>
        <span class="SLgc">unreachable</span>
}

</span></div>
<h3 id="Functions_and_Generic_Code">Functions and Generic Code</h3>
<p>Functions declare parameter and result types around <span class="code-inline">-&gt;</span>. A generic parameter appears after <span class="code-inline">func</span>; call-site inference normally supplies it.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span>(<span class="SCst">T</span>) <span class="SFct">tourClamp</span>(value, lower, upper: <span class="SCst">T</span>)-&gt;<span class="SCst">T</span>
{
    <span class="SLgc">if</span> value &lt; lower <span class="SLgc">do</span>
        <span class="SLgc">return</span> lower
    <span class="SLgc">if</span> value &gt; upper <span class="SLgc">do</span>
        <span class="SLgc">return</span> upper
    <span class="SLgc">return</span> value
}

<span class="SFct">#test</span>
{
    <span class="SItr">@assert</span>(<span class="SFct">tourClamp</span>(<span class="SNum">12</span>, <span class="SNum">0</span>, <span class="SNum">10</span>) == <span class="SNum">10</span>)
    <span class="SItr">@assert</span>(<span class="SFct">tourClamp</span>(<span class="SNum">0.25</span>'<span class="STpe">f32</span>, <span class="SNum">0.0</span>, <span class="SNum">1.0</span>) == <span class="SNum">0.25</span>)
}

</span></div>
<h3 id="Recoverable_Errors">Recoverable Errors</h3>
<p>A function marked <span class="code-inline">fail</span> may return an error instead of its normal result. <span class="code-inline">try</span> propagates that error, while <span class="code-inline">catch</span> handles it locally; capture it with 'as err' to inspect it.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">tourDivide</span>(numerator, denominator: <span class="STpe">s32</span>)-&gt;<span class="STpe">s32</span> <span class="SKwd">fail</span>
{
    <span class="SLgc">if</span> denominator == <span class="SNum">0</span> <span class="SLgc">do</span>
        <span class="SKwd">fail</span> <span class="SCst">Swag</span>.<span class="SCst">BaseError</span>{<span class="SStr">"division by zero"</span>}
    <span class="SLgc">return</span> numerator / denominator
}

<span class="SFct">#test</span>
{
    <span class="SItr">@assert</span>(<span class="SKwd">try</span> <span class="SFct">tourDivide</span>(<span class="SNum">12</span>, <span class="SNum">3</span>) == <span class="SNum">4</span>)

    <span class="SKwd">let</span> fallback = <span class="SKwd">catch</span> <span class="SFct">tourDivide</span>(<span class="SNum">12</span>, <span class="SNum">0</span>) <span class="SLgc">as</span> err
    <span class="SItr">@assert</span>(fallback == <span class="SNum">0</span>)
    <span class="SItr">@assert</span>(err != <span class="SKwd">null</span>)
}

</span></div>
<h3 id="Compile-Time_Programming">Compile-Time Programming</h3>
<p>Swag uses the same language during compilation. <span class="code-inline">#run</span> evaluates an expression at compile time; <span class="code-inline">#assert</span> then verifies the resulting constant before code generation starts.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">tourBuildMask</span>(bits: <span class="STpe">u32</span>)-&gt;<span class="STpe">u32</span>
{
    <span class="SLgc">return</span> (<span class="SNum">1</span>'<span class="STpe">u32</span> &lt;&lt; bits) - <span class="SNum">1</span>
}

<span class="SKwd">const</span> <span class="SCst">TourLowByteMask</span> = <span class="SFct">#run</span> <span class="SFct">tourBuildMask</span>(<span class="SNum">8</span>)
<span class="SCmp">#assert</span>(<span class="SCst">TourLowByteMask</span> == <span class="SNum">0xFF</span>)

</span></div>
<p>The rest of this reference expands each idea, including memory and nullability, custom operators, interfaces, compile-time reflection, safety checks, and code generation.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_001_003_hello_world_and_beyond_swg">Hello World and Beyond</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="The_Smallest_Executable">The Smallest Executable</h3>
<p><span class="code-inline">#main</span> is the entry point of an executable module. <span class="code-inline">@print</span> is a compiler intrinsic available without importing a standard module.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#main</span>
{
    <span class="SItr">@print</span>(<span class="SStr">"Hello, world!\n"</span>)
}
</span></div>
<p>Only one <span class="code-inline">#main</span> may exist in an executable. This reference uses <span class="code-inline">#test</span> blocks instead because the test runner owns the module entry point.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">const</span> <span class="SCst">ShowHelloOutput</span> = <span class="SKwd">false</span>

<span class="SFct">#test</span>
{
    <span class="SLgc">if</span> <span class="SCst">ShowHelloOutput</span> <span class="SLgc">do</span>
        <span class="SItr">@print</span>(<span class="SStr">"Hello, world!\n"</span>)
}

</span></div>
<h3 id="Compute_Part_of_the_Message_at_Compile_Time">Compute Part of the Message at Compile Time</h3>
<p>A function does not need a special compile-time implementation. <span class="code-inline">#run</span> asks the compiler to execute an ordinary function and embed its result.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">helloAudience</span>()-&gt;<span class="STpe">string</span>
{
    <span class="SLgc">return</span> <span class="SStr">"Swag"</span>
}

<span class="SKwd">const</span> <span class="SCst">HelloAudience</span> = <span class="SFct">#run</span> <span class="SFct">helloAudience</span>()
<span class="SCmp">#assert</span>(<span class="SCst">HelloAudience</span> == <span class="SStr">"Swag"</span>)

<span class="SFct">#test</span>
{
    <span class="SLgc">if</span> <span class="SCst">ShowHelloOutput</span> <span class="SLgc">do</span>
        <span class="SItr">@print</span>(<span class="SStr">"Hello, "</span>, <span class="SCst">HelloAudience</span>, <span class="SStr">"!\n"</span>)
}

</span></div>
<h3 id="Reusable_Compile-Time_Functions">Reusable Compile-Time Functions</h3>
<p><span class="code-inline">#[Swag.ConstExpr]</span> allows calls with constant arguments to participate in constant expressions without writing <span class="code-inline">#run</span> at every call site.</p>
<div class="code-block"><span class="SCde"><span class="SAtr">#[Swag.ConstExpr]</span>
<span class="SKwd">func</span> <span class="SFct">punctuation</span>(excited: <span class="STpe">bool</span>)-&gt;<span class="STpe">string</span>
{
    <span class="SLgc">return</span> excited ? <span class="SStr">"!"</span> : <span class="SStr">"."</span>
}

<span class="SKwd">const</span> <span class="SCst">HelloSuffix</span> = <span class="SFct">punctuation</span>(<span class="SKwd">true</span>)
<span class="SCmp">#assert</span>(<span class="SCst">HelloSuffix</span> == <span class="SStr">"!"</span>)

</span></div>
<h3 id="Generate_a_Declaration">Generate a Declaration</h3>
<p><span class="code-inline">#ast</span> returns source text that is parsed in place. This technique is reserved for cases where generics, mixins, or macros cannot express the required shape.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#ast</span>
{
    <span class="SLgc">return</span> <span class="SStr">"const GeneratedHello = \"Hello from generated code\""</span>
}

<span class="SCmp">#assert</span>(<span class="SCst">GeneratedHello</span> == <span class="SStr">"Hello from generated code"</span>)

</span></div>
<p>The progression is deliberate: start with normal runtime code, move pure work to compile time when it is useful, and generate source only when the program's structure itself must vary.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_001_004_swc_command_line_swg">Swc Command Line</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>
</span></div>
<h3 id="The__swc__Command_Line">The <span class="code-inline">swc</span> Command Line</h3>
<p>The language is named Swag; the compiler executable is <span class="code-inline">swc</span>. Ask the installed binary for the authoritative option set:</p>
<div class="code-block"><span class="SCde">swc help
swc help test
</span></div>
<p>The current commands are:</p>
<table class="table-markdown">
<tr><th>Command</th><th>Purpose</th></tr>
<tr><td><span class="code-inline">build</span></td><td>Compile and emit native artifacts without running them</td></tr>
<tr><td><span class="code-inline">run</span></td><td>Build, then run emitted executables</td></tr>
<tr><td><span class="code-inline">test</span></td><td>Run source-driven tests and <span class="code-inline">#test</span> functions</td></tr>
<tr><td><span class="code-inline">format</span></td><td>Rewrite source using canonical formatting</td></tr>
<tr><td><span class="code-inline">syntax</span></td><td>Parse source without semantic analysis or code generation</td></tr>
<tr><td><span class="code-inline">sema</span></td><td>Parse and type-check source without backend code generation</td></tr>
<tr><td><span class="code-inline">doc</span></td><td>Parse and type-check source, then generate configured documentation</td></tr>
<tr><td><span class="code-inline">unittest</span></td><td>Run the compiler's internal C++ unit tests</td></tr>
</table>
<p>There is no <span class="code-inline">new</span> project generator in the current CLI.</p>
<h3 id="Selecting_Input">Selecting Input</h3>
<p>Use one input model per invocation:</p>
<table class="table-markdown">
<tr><th>Option</th><th>Meaning</th></tr>
<tr><td>'--workspace PATH', '-w PATH'</td><td>Use a workspace containing <span class="code-inline">modules/&lt;name&gt;</span></td></tr>
<tr><td>'--workspace-module NAME', '-m NAME'</td><td>Select one module inside that workspace</td></tr>
<tr><td>'--module PATH', '-mf PATH'</td><td>Compile a module directly</td></tr>
<tr><td>'--module-file PATH'</td><td>Run one module setup file, then compile its module</td></tr>
<tr><td>'--directory PATH', '-d PATH'</td><td>Add a directory of source files</td></tr>
<tr><td>'--file PATH', '-f PATH'</td><td>Add an individual source file</td></tr>
</table>
<p><span class="code-inline">--workspace</span> and <span class="code-inline">--workspace-module</span> are available to <span class="code-inline">build</span>, <span class="code-inline">run</span>, <span class="code-inline">test</span>, <span class="code-inline">sema</span>, and <span class="code-inline">doc</span>. The <span class="code-inline">format</span>, <span class="code-inline">syntax</span>, and compiler-internal <span class="code-inline">unittest</span> commands use the direct module, module-file, directory, or file modes instead.</p>
<p>Where workspace mode is accepted, it excludes the direct module, directory, and file input modes. <span class="code-inline">--workspace-module</span> is meaningful only with <span class="code-inline">--workspace</span>.</p>
<h3 id="Build_Configurations">Build Configurations</h3>
<p><span class="code-inline">--build-cfg</span> (or <span class="code-inline">-bc</span>) accepts:</p>
<table class="table-markdown">
<tr><th>Value</th><th>Intended use</th></tr>
<tr><td><span class="code-inline">debug</span></td><td>Full safety/sanity, allocation diagnostics, no optimization</td></tr>
<tr><td><span class="code-inline">fast-debug</span></td><td>Default: full safety/sanity with optimized code and lighter allocation tracking</td></tr>
<tr><td><span class="code-inline">release</span></td><td>Optimized code, static sanity on, runtime safety and tracking off</td></tr>
</table>
<p>The target architecture currently exposed by <span class="code-inline">--arch</span> is <span class="code-inline">x86_64</span>. Select the artifact with <span class="code-inline">--artifact-kind</span> (<span class="code-inline">-ak</span>): <span class="code-inline">executable</span>, <span class="code-inline">shared-library</span>, <span class="code-inline">static-library</span>, or <span class="code-inline">export</span>.</p>
<h3 id="Common_Workflows">Common Workflows</h3>
<div class="code-block"><span class="SCde">swc build -w &lt;workspace&gt; -m app -bc release
swc run   -w &lt;workspace&gt; -m app --run-arg first --run-arg second
swc sema  -w &lt;workspace&gt; -m app
swc doc   -w &lt;workspace&gt; -m app --doc-output-dir &lt;directory&gt;
swc syntax -mf &lt;workspace&gt;/modules/app
swc format -mf &lt;workspace&gt;/modules/app --dry-run
</span></div>
<p><span class="code-inline">--dry-run</span> previews planned stages without executing compile-time code, native tools, tests, or emitted programs. <span class="code-inline">--show-config</span> prints the resolved command, environment, toolchain, and artifact configuration, then exits.</p>
<h3 id="Documentation_Generation">Documentation Generation</h3>
<p>'swc doc' uses the module's <span class="code-inline">BuildCfg.genDoc</span> configuration. The documentation kind can generate a public API page, a numbered examples document, or one page per source file.</p>
<table class="table-markdown">
<tr><th>Option</th><th>Effect</th></tr>
<tr><td>'--doc-output-dir PATH'</td><td>Write generated pages under <span class="code-inline">PATH</span></td></tr>
<tr><td>'--css PATH'</td><td>Override the configured stylesheet link</td></tr>
<tr><td>'--ext EXTENSION'</td><td>Override the configured output extension</td></tr>
<tr><td><span class="code-inline">--output-doc</span> / <span class="code-inline">--no-output-doc</span></td><td>Enable or suppress documentation files</td></tr>
</table>
<p>The command also generates the public runtime API page once per output directory. Use <span class="code-inline">--rebuild</span> when regenerating a workspace after source or documentation changes.</p>
<h3 id="Test_Controls">Test Controls</h3>
<p>By default, 'swc test' runs <span class="code-inline">#test</span> functions through both the JIT and native backend and emits native output. Narrow that behavior when diagnosing a layer:</p>
<table class="table-markdown">
<tr><th>Option</th><th>Effect</th></tr>
<tr><td><span class="code-inline">--test-jit</span>, <span class="code-inline">-tj</span> / <span class="code-inline">--no-test-jit</span></td><td>Enable or disable JIT tests</td></tr>
<tr><td><span class="code-inline">--test-native</span>, <span class="code-inline">-tn</span> / <span class="code-inline">--no-test-native</span></td><td>Enable or disable native tests</td></tr>
<tr><td><span class="code-inline">--output</span> / <span class="code-inline">--no-output</span></td><td>Enable or disable native artifact generation</td></tr>
<tr><td><span class="code-inline">--lex-only</span></td><td>Stop after lexing source-driven tests</td></tr>
<tr><td><span class="code-inline">--syntax-only</span></td><td>Stop after parsing</td></tr>
<tr><td><span class="code-inline">--sema-only</span></td><td>Stop after semantic analysis</td></tr>
<tr><td><span class="code-inline">--verbose-verify</span>, <span class="code-inline">-vv</span></td><td>Show diagnostics normally consumed by expected-error tests</td></tr>
</table>
<p>The three <span class="code-inline">*-only</span> modes are mutually exclusive. For this reference, keep the default JIT and native paths enabled so examples verify both execution engines.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h2 id="_002_000_modules_and_source_code_swg">Modules and Source Code</h2>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>
</span></div>
<p>A Swag program is organized as source files inside modules, and modules inside a workspace. This chapter covers setup files, dependencies, declaration order, comments, statement termination, identifiers, sigils, visibility, and module lifecycle hooks.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_002_001_workspaces_modules_and_dependencies_swg">Workspaces Modules and Dependencies</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Workspaces_and_Modules">Workspaces and Modules</h3>
<p>A <b>workspace</b> is the unit selected by the command line. Its <span class="code-inline">modules</span> directory contains one folder per module. A <b>module</b> is the compilation and API boundary: it produces an executable, library, or exported API description.</p>
<div class="code-block"><span class="SCde">my-workspace/
└── modules/
    ├── app/
    │   ├── module.swg
    │   └── src/
    │       └── main.swg
    └── support/
        ├── module.swg
        └── src/
            └── support.swg
</span></div>
<p>The module folder name is its default name. All <span class="code-inline">.swg</span> files below <span class="code-inline">src</span> belong to that module; their subdirectories are organizational and do not create namespaces.</p>
<div class="code-block"><span class="SCde">
<span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(<span class="SCmp">#module</span>) == <span class="STpe">string</span>)

</span></div>
<h3 id="The__module_swg__File">The <span class="code-inline">module.swg</span> File</h3>
<p><span class="code-inline">module.swg</span> executes at compile time and configures the current module through <span class="code-inline">@compiler</span>. A minimal executable configuration looks like this:</p>
<div class="code-block"><span class="SCde"><span class="SFct">#run</span>
{
    <span class="SKwd">let</span> cfg = <span class="SKwd">notnull</span> <span class="SItr">@compiler</span>.<span class="SFct">getBuildCfg</span>()
    cfg.moduleVersion  = <span class="SNum">1</span>
    cfg.moduleRevision = <span class="SNum">0</span>
    cfg.moduleBuildNum = <span class="SNum">0</span>
    cfg.backendKind    = .<span class="SCst">Executable</span>
}
</span></div>
<p>Common backend kinds are <span class="code-inline">.Executable</span>, <span class="code-inline">.SharedLibrary</span>, <span class="code-inline">.StaticLibrary</span>, and <span class="code-inline">.Export</span>. A module can also set <span class="code-inline">moduleNamespace</span> when its public API should live under an explicit root namespace.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="Importing_Another_Module">Importing Another Module</h3>
<p>Imports belong in <span class="code-inline">module.swg</span>. The following form imports the standard <span class="code-inline">core</span> module from the compiler's standard workspace:</p>
<div class="code-block"><span class="SCde"><span class="SCmp">#import</span>(<span class="SStr">"core"</span>, location: <span class="SStr">"swag@std"</span>)
</span></div>
<p>An import makes the dependency's public API available and ensures that the dependency is built first. It does not import all names into the current lexical scope; use qualified names or a targeted <span class="code-inline">using</span> declaration in source files.</p>
<div class="blockquote blockquote-note">
<div class="blockquote-title-block"><span class="blockquote-title">Note</span></div>
<p><span class="code-inline">#load</span> includes source selected by the compiler, while <span class="code-inline">#import</span> establishes a module dependency. They solve different problems and are not interchangeable.</p>
</div>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_002_002_source_files_swg">Source Files</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>
</span></div>
<h3 id="Source_Files">Source Files</h3>
<p>Regular Swag source files use the <span class="code-inline">.swg</span> extension and UTF-8 encoding. A module compiles every <span class="code-inline">.swg</span> file below its <span class="code-inline">src</span> directory as one program. Directory names do not affect symbol names, declaration order, or visibility.</p>
<p>Because module files are compiled together:</p>
<ul>
<li>declarations may be used before their textual definition;</li>
<li>a declaration in one file can refer to a declaration in another;</li>
<li><span class="code-inline">private</span> declarations remain file-local;</li>
<li><span class="code-inline">internal</span> and <span class="code-inline">public</span> declarations share the module namespace.</li>
</ul>
<p>Use files and folders to group concepts for readers, then use namespaces when the qualified program name should also express that grouping.</p>
<h3 id="Script_Files">Script Files</h3>
<p>The <span class="code-inline">.swgs</span> extension is reserved for standalone scripts. A script is compiled as an individual input rather than discovered as part of a workspace module. Use <span class="code-inline">.swg</span> for reusable application and library code.</p>
<div class="blockquote blockquote-note">
<div class="blockquote-title-block"><span class="blockquote-title">Note</span></div>
<p>The compiler, not the host filesystem order, determines compilation. Never rely on file names to initialize runtime state; use <span class="code-inline">#init</span> and explicit dependencies between values instead.</p>
</div>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_002_003_global_declaration_order_swg">Global Declaration Order</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Top-Level_Declaration_Order">Top-Level Declaration Order</h3>
<p>The order of all <b>top-level</b> declarations in Swag does not matter. This means you can reference constants, variables, or functions before they are defined — either within the same file or across multiple files.</p>
<p>This flexibility is especially useful in large codebases, where logical flow or readability may benefit from organizing code independently of declaration order.</p>
<div class="code-block"><span class="SCde">
<span class="SCmt">// In this example, we declare a constant 'A' and initialize it with 'B',</span>
<span class="SCmt">// even though 'B' has not yet been declared or defined.</span>
<span class="SKwd">const</span> <span class="SCst">A</span> = <span class="SCst">B</span>

<span class="SCmt">// Next, we declare a constant 'B' and initialize it with 'C',</span>
<span class="SCmt">// which is also not yet declared or defined.</span>
<span class="SKwd">const</span> <span class="SCst">B</span> = <span class="SCst">C</span>

<span class="SCmt">// Finally, we declare and define 'C' as a constant of type 'u64'</span>
<span class="SCmt">// (an unsigned 64-bit integer) with a value of 1.</span>
<span class="SCmt">// This retroactively assigns values to both 'A' and 'B'</span>
<span class="SCmt">// based on the earlier assignments.</span>
<span class="SKwd">const</span> <span class="SCst">C</span>: <span class="STpe">u64</span> = <span class="SNum">1</span>

</span></div>
<p>In this example, we demonstrate Swag's flexibility by calling the function <span class="code-inline">functionDeclaredLater</span> before it is defined. This behavior illustrates that Swag does not impose order restrictions on function declarations.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#run</span>
{
    <span class="SCmt">// Call the function 'functionDeclaredLater' before it is declared.</span>
    <span class="SCmt">// Swag allows this because top-level declarations are order-independent.</span>
    <span class="SFct">functionDeclaredLater</span>()
}

<span class="SCmt">// The function is declared here, after it has already been called.</span>
<span class="SKwd">func</span> <span class="SFct">functionDeclaredLater</span>() {}

</span></div>
<p>This flexibility also applies across multiple files. For example, you can call a function in one file and define it in another. Swag's global declaration model is intentionally non-restrictive, allowing you to structure your code in the way that best supports clarity and maintainability.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_002_004_comments_swg">Comments</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Comments">Comments</h3>
<p>Swag supports both single-line and multi-line comments, providing flexibility for inline documentation and explanations within your code. This helps maintain clarity and readability, especially in larger or more complex codebases.</p>
<div class="code-block"><span class="SCde">
<span class="SCmt">// Example of a single-line comment</span>
<span class="SCmt">// Single-line comments are typically used for brief explanations or notes.</span>

<span class="SCmt">/*
    Example of a multi-line comment
    that spans several lines.

    Multi-line comments are useful when more detailed explanations are required.
    These comments can describe the overall purpose of a function, document complex
    logic, or provide additional context to developers.
*/</span>

<span class="SKwd">const</span> <span class="SCst">A</span> = <span class="SNum">0</span>                   <span class="SCmt">// A constant named 'A' assigned the value '0'.</span>
<span class="SKwd">const</span> <span class="SCst">B</span> = <span class="SCmt">/* false */</span><span class="SKwd">true</span>     <span class="SCmt">// A constant named 'B' assigned the value 'true', with an inline</span>
<span class="SCmt">// comment noting that 'false' was an alternative value considered.</span>

</span></div>
<h3 id="Nested_Comments">Nested Comments</h3>
<p>Swag also supports nested comments within multi-line comments. This can be particularly useful when temporarily disabling a block of code or when adding notes inside an existing comment block.</p>
<div class="code-block"><span class="SCde">
<span class="SCmt">/*
    /* Example of a nested multi-line comment */
    The nested comment above is encapsulated within another multi-line comment.
    This demonstrates Swag's ability to handle complex comment structures without
    causing errors or ambiguity.
*/</span>

</span></div>
<h3 id="_002_005_semicolons_swg">Semicolons</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Statement_Termination_in_Swag">Statement Termination in Swag</h3>
<p>Unlike languages such as C or C++, there is no strict requirement to end statements with a semicolon (<span class="code-inline">;</span>). In Swag, a statement naturally terminates at the end of a line ('end of line'). This allows for cleaner, more concise syntax and reduces visual clutter, making the code easier to read and maintain.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SCmt">// Declare two variables, 'x' and 'y', both of type 's32' (signed 32-bit integer),</span>
    <span class="SCmt">// and initialize them with the value '1'.</span>
    <span class="SKwd">var</span> x, y: <span class="STpe">s32</span> = <span class="SNum">1</span>

    <span class="SCmt">// Increment the value of both 'x' and 'y' by 1.</span>
    x += <span class="SNum">1</span>
    y += <span class="SNum">1</span>

    <span class="SCmt">// Use the '@assert' intrinsic to verify the correctness of the logic.</span>
    <span class="SItr">@assert</span>(x == <span class="SNum">2</span>)     <span class="SCmt">// Confirms that 'x' equals 2. Raises an error if it fails.</span>
    <span class="SItr">@assert</span>(y == x)     <span class="SCmt">// Confirms that 'y' equals 'x', which should also be 2.</span>
}

</span></div>
<h3 id="Bodyless_Declarations">Bodyless Declarations</h3>
<p>Declarations without a body also terminate at the end of the line. Interface methods and foreign functions do not need a special terminator.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">interface</span> <span class="SCst">Counter</span>
{
    <span class="SKwd">mtd</span> <span class="SFct">value</span>()-&gt;<span class="STpe">u64</span>
    <span class="SKwd">mtd</span> <span class="SFct">reset</span>()
}

</span></div>
<h3 id="Semicolons">Semicolons</h3>
<p>A trailing semicolon is accepted but redundant. Its useful role is to separate multiple statements written on the same line. Use that compact form sparingly because it can make control flow harder to scan.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SCmt">// Two variable declarations and initializations on a single line.</span>
    <span class="SKwd">var</span> x = <span class="SNum">0</span>
    <span class="SKwd">var</span> y = <span class="SNum">0</span>

    <span class="SCmt">// Increment both 'x' and 'y' on the same line.</span>
    x += <span class="SNum">1</span>; y += <span class="SNum">1</span>

    <span class="SCmt">// Assert correctness of both variables.</span>
    <span class="SItr">@assert</span>(x == <span class="SNum">1</span>)
    <span class="SItr">@assert</span>(y == <span class="SNum">1</span>)
}

</span></div>
<h3 id="_002_006_identifiers_swg">Identifiers</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Naming">Naming</h3>
<p>User-defined identifiers, such as variables, constants, and function names, must begin with either an underscore (<span class="code-inline">_</span>) or an ASCII letter. Identifiers may then include underscores, ASCII letters, and digits.</p>
<p>Examples:</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">const</span> thisIsAValidIdentifier0   = <span class="SNum">0</span>
<span class="SKwd">const</span> this_is_also_valid        = <span class="SNum">0</span>
<span class="SKwd">const</span> this_1_is_2_also__3_valid = <span class="SNum">0</span>

</span></div>
<p>However, identifiers cannot start with two underscores, as this prefix is reserved by the compiler.</p>
<div class="code-block"><span class="SCde">
<span class="SCmt">// const __this_is_invalid = 0</span>

</span></div>
<h3 id="Compiler_Instructions">Compiler Instructions</h3>
<p>Names beginning with <span class="code-inline">#</span> belong to compiler syntax: built-in directives, static queries, qualifiers, modifiers, and user-defined selectors at specific extension points such as custom iteration.</p>
<p>Examples of compiler instructions:</p>
<div class="code-block"><span class="SCde"><span class="SCmp">#assert</span>
<span class="SFct">#run</span>
<span class="SFct">#main</span>
</span></div>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="Intrinsics">Intrinsics</h3>
<p>Names beginning with <span class="code-inline">@</span> represent compiler-provided intrinsic values and operations. Availability depends on the intrinsic and context: <span class="code-inline">@compiler</span> is compile-time only, while math and memory intrinsics can also generate runtime code.</p>
<p>Examples of intrinsic functions:</p>
<div class="code-block"><span class="SCde"><span class="SItr">@min</span>()
<span class="SItr">@max</span>()
<span class="SItr">@sqrt</span>()
<span class="SItr">@print</span>()
</span></div>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_002_007_keywords_swg">Keywords</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>
</span></div>
<h3 id="Language_Keyword_Index">Language Keyword Index</h3>
<p>Keywords are reserved bare words. They cannot be reused as identifiers. This page is an index; the surrounding chapters explain each active construct.</p>
<h3 id="Declarations_and_Organization">Declarations and Organization</h3>
<div class="code-block"><span class="SCde"><span class="SKwd">alias</span>  <span class="SKwd">attr</span>  <span class="SKwd">const</span>  <span class="SKwd">enum</span>  <span class="SKwd">func</span>  <span class="SKwd">impl</span>  <span class="SKwd">interface</span>  <span class="SKwd">internal</span>
<span class="SKwd">let</span>  <span class="SKwd">mtd</span>  <span class="SKwd">namespace</span>  <span class="SKwd">private</span>  <span class="SKwd">public</span>  <span class="SKwd">struct</span>  <span class="SKwd">union</span>  <span class="SKwd">using</span>  <span class="SKwd">var</span>  <span class="SKwd">with</span>
</span></div>
<p><span class="code-inline">me</span> names the receiver inside methods.</p>
<h3 id="Control_Flow_and_Expressions">Control Flow and Expressions</h3>
<div class="code-block"><span class="SCde"><span class="SLgc">and</span>  <span class="SLgc">as</span>  <span class="SLgc">break</span>  <span class="SLgc">case</span>  <span class="SLgc">continue</span>  <span class="SLgc">default</span>  <span class="SLgc">defer</span>  <span class="SLgc">do</span>  <span class="SLgc">elif</span>  <span class="SLgc">else</span>
<span class="SLgc">fallthrough</span>  <span class="SLgc">for</span>  <span class="SLgc">if</span>  <span class="SLgc">in</span>  <span class="SLgc">is</span>  <span class="STpe">me</span>  <span class="SLgc">or</span>  <span class="SLgc">orelse</span>  <span class="SLgc">return</span>  <span class="SLgc">switch</span>
<span class="SLgc">to</span>  <span class="SLgc">unreachable</span>  <span class="SLgc">until</span>  <span class="SLgc">where</span>  <span class="SLgc">while</span>
</span></div>
<p><span class="code-inline">foreach</span> is no longer part of the language; the compiler recognizes it only to produce a migration diagnostic that points to <span class="code-inline">for</span>.</p>
<p><span class="code-inline">verify</span> is no longer part of the language either, and is now an ordinary identifier. It used to be accepted on function declarations but was never executed. Express a compile-time overload contract with a <span class="code-inline">where</span> constraint, and a runtime precondition with ordinary code.</p>
<h3 id="Values__Errors__and_Conversion">Values, Errors, and Conversion</h3>
<div class="code-block"><span class="SCde"><span class="SKwd">cast</span>  <span class="SKwd">catch</span>  <span class="SKwd">discard</span>  <span class="SKwd">dref</span>  <span class="SKwd">expect</span>  <span class="SKwd">fail</span>  <span class="SKwd">false</span>  <span class="SKwd">notnull</span>
<span class="SKwd">null</span>  <span class="SKwd">retval</span>  <span class="SKwd">true</span>  <span class="SKwd">try</span>  <span class="SKwd">undefined</span>
</span></div>
<p><span class="code-inline">not</span> is reserved for future use.</p>
<h3 id="Contextual_Source_and_Module_Names">Contextual Source and Module Names</h3>
<p><span class="code-inline">export</span>, <span class="code-inline">generated</span>, <span class="code-inline">location</span>, <span class="code-inline">link</span>, and <span class="code-inline">version</span> are recognized in specific module-setup or generated-source positions. Outside those positions the lexer treats them as ordinary identifiers; they are not part of the reserved keyword set above.</p>
<h3 id="Built-In_Types">Built-In Types</h3>
<div class="code-block"><span class="SCde"><span class="STpe">any</span>  <span class="STpe">bool</span>  <span class="STpe">cstring</span>  <span class="STpe">cvarargs</span>  <span class="STpe">f32</span>  <span class="STpe">f64</span>  <span class="STpe">rune</span>
<span class="STpe">s8</span>  <span class="STpe">s16</span>  <span class="STpe">s32</span>  <span class="STpe">s64</span>  <span class="STpe">string</span>  <span class="STpe">typeinfo</span>
<span class="STpe">u8</span>  <span class="STpe">u16</span>  <span class="STpe">u32</span>  <span class="STpe">u64</span>  <span class="STpe">void</span>
</span></div>
<h3 id="Compiler_Directives">Compiler Directives</h3>
<p>Directives introduce compiler-executed blocks, conditional compilation, module configuration, source inclusion, diagnostics, and code injection.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#ast</span>  <span class="SCmp">#assert</span>  <span class="SItr">#code</span>  <span class="SFct">#dependencies</span>  <span class="SCmp">#error</span>
<span class="SCmp">#foreignlib</span>  <span class="SCmp">#global</span>  <span class="SCmp">#import</span>  <span class="SItr">#include</span>  <span class="SCmp">#inject</span>
<span class="SCmp">#load</span>  <span class="SFct">#main</span>  <span class="SFct">#message</span>  <span class="SFct">#premain</span>  <span class="SCmp">#print</span>  <span class="SFct">#run</span>  <span class="SCmp">#scope</span>
<span class="SCmp">#static</span>  <span class="SFct">#test</span>  <span class="SItr">#type</span>  <span class="SCmp">#warning</span>  <span class="SFct">#init</span>  <span class="SFct">#drop</span>
</span></div>
<h3 id="Compile-Time_Introspection">Compile-Time Introspection</h3>
<div class="code-block"><span class="SCde"><span class="SItr">#alignof</span>  <span class="SItr">#defined</span>  <span class="SItr">#decltype</span>  <span class="SItr">#fullnameof</span>  <span class="SItr">#gettag</span>  <span class="SItr">#hastag</span>
<span class="SItr">#isconstexpr</span>  <span class="SItr">#kindof</span>  <span class="SItr">#location</span>  <span class="SItr">#nameof</span>  <span class="SItr">#offsetof</span>  <span class="SItr">#runes</span>
<span class="SItr">#safety</span>  <span class="SItr">#sanity</span>  <span class="SItr">#sizeof</span>  <span class="SItr">#stringof</span>  <span class="SItr">#typeof</span>
</span></div>
<h3 id="Compiler_Context_Values">Compiler Context Values</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#arch</span>  <span class="SCmp">#callerlocation</span>  <span class="SCmp">#cfg</span>  <span class="SCmp">#command</span>  <span class="SCmp">#cpu</span>  <span class="SCmp">#curlocation</span>
<span class="SCmp">#file</span>  <span class="SCmp">#line</span>  <span class="SCmp">#module</span>  <span class="SCmp">#os</span>  <span class="SCmp">#scopename</span>  <span class="SCmp">#swcbuildnum</span>
<span class="SCmp">#swagos</span>  <span class="SCmp">#swcrevision</span>  <span class="SCmp">#swcversion</span>
</span></div>
<p>Collision-free compiler identifiers for mixins and macros:</p>
<div class="code-block"><span class="SCde"><span class="SItr">#uniq0</span>  <span class="SItr">#uniq1</span>  <span class="SItr">#uniq2</span>  <span class="SItr">#uniq3</span>  <span class="SItr">#uniq4</span>
<span class="SItr">#uniq5</span>  <span class="SItr">#uniq6</span>  <span class="SItr">#uniq7</span>  <span class="SItr">#uniq8</span>  <span class="SItr">#uniq9</span>
</span></div>
<h3 id="Modifiers">Modifiers</h3>
<p>Modifiers refine the type, operand, conversion, literal, or statement that follows them. They annotate what carries no symbol; a declaration takes an attribute instead.</p>
<div class="code-block"><span class="SCde"><span class="SItr">#bit</span>  <span class="SItr">#complete</span>  <span class="SItr">#fail</span>  <span class="SItr">#fwd</span>  <span class="SItr">#move</span>  <span class="SItr">#nodrop</span>  <span class="SItr">#nofail</span>  <span class="SItr">#null</span>
<span class="SItr">#prom</span>  <span class="SItr">#raw</span>  <span class="SItr">#relocate</span>  <span class="SItr">#reverse</span>  <span class="SItr">#unconst</span>  <span class="SItr">#wrap</span>
</span></div>
<h3 id="Runtime_and_Compiler_Intrinsics">Runtime and Compiler Intrinsics</h3>
<p>Intrinsic values:</p>
<div class="code-block"><span class="SCde"><span class="SItr">@args</span>  <span class="SItr">@compiler</span>  <span class="SItr">@gvtd</span>  <span class="SItr">@index</span>  <span class="SItr">@jit</span>
<span class="SItr">@modules</span>  <span class="SItr">@pinfos</span>  <span class="SItr">@rtflags</span>
</span></div>
<p>Type, value, lifecycle, and control intrinsics:</p>
<div class="code-block"><span class="SCde"><span class="SItr">@as</span>  <span class="SItr">@assert</span>  <span class="SItr">@breakpoint</span>  <span class="SItr">@compilererror</span>  <span class="SItr">@compilerwarning</span>
<span class="SItr">@countof</span>  <span class="SItr">@dataof</span>  <span class="SItr">@drop</span>  <span class="SItr">@getcontext</span>  <span class="SItr">@init</span>  <span class="SItr">@is</span>  <span class="SItr">@isset</span>
<span class="SItr">@kindof</span>  <span class="SItr">@mkany</span>  <span class="SItr">@mkinterface</span>  <span class="SItr">@mkslice</span>  <span class="SItr">@mkstring</span>  <span class="SItr">@panic</span>
<span class="SItr">@postcopy</span>  <span class="SItr">@postmove</span>  <span class="SItr">@print</span>  <span class="SItr">@safetypanic</span>  <span class="SItr">@setcontext</span>
<span class="SItr">@stringcmp</span>  <span class="SItr">@tableof</span>  <span class="SItr">@typecmp</span>
</span></div>
<p>Math and bit intrinsics:</p>
<div class="code-block"><span class="SCde"><span class="SItr">@abs</span>  <span class="SItr">@acos</span>  <span class="SItr">@asin</span>  <span class="SItr">@atan</span>  <span class="SItr">@atan2</span>  <span class="SItr">@bitcountlz</span>  <span class="SItr">@bitcountnz</span>
<span class="SItr">@bitcounttz</span>  <span class="SItr">@byteswap</span>  <span class="SItr">@ceil</span>  <span class="SItr">@cos</span>  <span class="SItr">@cosh</span>  <span class="SItr">@exp</span>  <span class="SItr">@exp2</span>
<span class="SItr">@floor</span>  <span class="SItr">@log</span>  <span class="SItr">@log10</span>  <span class="SItr">@log2</span>  <span class="SItr">@max</span>  <span class="SItr">@min</span>  <span class="SItr">@muladd</span>  <span class="SItr">@pow</span>
<span class="SItr">@rol</span>  <span class="SItr">@ror</span>  <span class="SItr">@round</span>  <span class="SItr">@sin</span>  <span class="SItr">@sinh</span>  <span class="SItr">@sqrt</span>  <span class="SItr">@tan</span>  <span class="SItr">@tanh</span>  <span class="SItr">@trunc</span>
</span></div>
<p>Memory, atomic, and C variadic intrinsics:</p>
<div class="code-block"><span class="SCde"><span class="SItr">@alloc</span>  <span class="SItr">@atomadd</span>  <span class="SItr">@atomand</span>  <span class="SItr">@atomcmpxchg</span>  <span class="SItr">@atomor</span>  <span class="SItr">@atomxchg</span>
<span class="SItr">@atomxor</span>  <span class="SItr">@cvaarg</span>  <span class="SItr">@cvaend</span>  <span class="SItr">@cvastart</span>  <span class="SItr">@free</span>  <span class="SItr">@memcmp</span>
<span class="SItr">@memcpy</span>  <span class="SItr">@memmove</span>  <span class="SItr">@memset</span>  <span class="SItr">@realloc</span>
</span></div>
<div class="blockquote blockquote-note">
<div class="blockquote-title-block"><span class="blockquote-title">Note</span></div>
<p>The <span class="code-inline">#</span>-prefixed and <span class="code-inline">@</span>-prefixed names are reserved separately from bare identifiers. The next section explains why Swag uses both namespaces.</p>
</div>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_002_008_sigils_swg">Sigils</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Compiler_Names______and____">Compiler Names: <span class="code-inline">#</span> and <span class="code-inline">@</span></h3>
<p>Swag gives two prefixed name families special syntactic roles. They cannot collide with ordinary identifiers:</p>
<ul>
<li><span class="code-inline">#</span> introduces directives, compile-time queries, and modifiers.</li>
<li><span class="code-inline">@</span> introduces intrinsic values and operations implemented by the compiler</li>
</ul>
<p>or runtime.</p>
<p>The prefix describes the facility's role, not necessarily when it executes. An intrinsic such as <span class="code-inline">@min</span> works in compile-time code and runtime code; <span class="code-inline">@compiler</span> is available only at compile time.</p>
<p>Some extension points also accept a user-defined sharp selector. For example, 'for #Pairs ...' resolves the custom iteration hook <span class="code-inline">opVisitPairs</span>. Such a selector is still part of <span class="code-inline">#</span>-syntax; it does not create an ordinary identifier named <span class="code-inline">#Pairs</span>.</p>
<h3 id="Modifier_or_Attribute">Modifier or Attribute</h3>
<p>A modifier and an attribute both annotate code, so one rule decides which is which:</p>
<div class="blockquote blockquote-default">
<p>An attribute annotates something that has a <b>symbol</b>. A modifier annotates something that does not.</p>
</div>
<p>An attribute is a named, parameterized annotation attached to a declaration, so it can be reflected (<span class="code-inline">TypeInfoStruct.attributes</span>), declared by user code with <span class="code-inline">attr</span>, and inherited by everything a block contains. A type, an operand, a conversion, a literal, or a statement carries no symbol: reflection could never report an annotation there, so those take a modifier instead.</p>
<p>The rule fixes the properties of each family:</p>
<table class="table-markdown">
<tr><th></th><th>Modifier</th><th>Attribute</th></tr>
<tr><td>Set</td><td>closed, compiler-defined</td><td>open, <span class="code-inline">attr</span> declares more</td></tr>
<tr><td>Target</td><td>type, operand, cast, literal, statement</td><td>declaration, lexical scope</td></tr>
<tr><td>Parameters</td><td>never</td><td>yes</td></tr>
<tr><td>Reflection</td><td>never</td><td>yes</td></tr>
<tr><td>Inherited by a scope</td><td>never</td><td>yes</td></tr>
</table>
<p><span class="code-inline">Swag.AttrUsage</span> names the declaration kinds an attribute accepts, and the compiler rejects the attribute anywhere else. A block is the exception: it broadcasts to the declarations it contains, and each of those is checked on its own.</p>
<h3 id="Directives_and_Static_Queries">Directives and Static Queries</h3>
<p>Directives shape compilation or declare compiler-managed entry points:</p>
<div class="code-block"><span class="SCde"><span class="SCmp">#static</span> <span class="SLgc">if</span> <span class="SCst">DEBUG</span>
{
    <span class="SCmt">// Included only when DEBUG is a compile-time true value.</span>
}
<span class="SFct">#run</span> { <span class="SFct">generateTables</span>() }
<span class="SFct">#test</span> { <span class="SItr">@assert</span>(<span class="SFct">parse</span>(<span class="SStr">"ok"</span>)) }
</span></div>
<p>Static queries produce facts known by semantic analysis:</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">const</span> <span class="SCst">Answer</span> = <span class="SNum">42</span>

    <span class="SCmp">#assert</span>(<span class="SItr">#sizeof</span>(<span class="STpe">s32</span>) == <span class="SNum">4</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#alignof</span>(<span class="STpe">s32</span>) == <span class="SNum">4</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(<span class="SCst">Answer</span>) == <span class="STpe">s32</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#stringof</span>(<span class="SCst">Answer</span>) == <span class="SStr">"42"</span>)
}

</span></div>
<p><span class="code-inline">#assert</span> itself runs during compilation. If its condition is not a constant <span class="code-inline">bool</span>, compilation fails.</p>
<h3 id="Intrinsic_Values_and_Operations">Intrinsic Values and Operations</h3>
<p>Intrinsics participate in expressions. Some expose context (<span class="code-inline">@index</span>, <span class="code-inline">@args</span>, <span class="code-inline">@getcontext</span>), some construct runtime-shaped values (<span class="code-inline">@mkslice</span>, <span class="code-inline">@mkany</span>), and some perform primitive operations (<span class="code-inline">@sqrt</span>, <span class="code-inline">@memcpy</span>, <span class="code-inline">@atomadd</span>).</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> values: <span class="SKwd">const</span> [..] <span class="STpe">s32</span> = [<span class="SNum">10</span>, <span class="SNum">20</span>, <span class="SNum">30</span>]

    <span class="SItr">@assert</span>(<span class="SItr">@countof</span>(values) == <span class="SNum">3</span>)
    <span class="SKwd">let</span> data = <span class="SItr">@dataof</span>(values)
    <span class="SItr">@assert</span>(data[<span class="SNum">1</span>] == <span class="SNum">20</span>)

    <span class="SCmt">// The same intrinsic can be evaluated by the compiler in a constant context.</span>
    <span class="SKwd">const</span> <span class="SCst">Minimum</span> = <span class="SItr">@min</span>(<span class="SNum">7</span>'<span class="STpe">s32</span>, <span class="SNum">3</span>'<span class="STpe">s32</span>)
    <span class="SCmp">#assert</span>(<span class="SCst">Minimum</span> == <span class="SNum">3</span>)
}

</span></div>
<h3 id="Related_Names_with_Different_Semantics">Related Names with Different Semantics</h3>
<p>Some concepts have both a directive and an intrinsic:</p>
<table class="table-markdown">
<tr><th>Compile-time form</th><th>Intrinsic form</th></tr>
<tr><td><span class="code-inline">#assert(condition)</span> rejects the build</td><td><span class="code-inline">@assert(condition)</span> checks in its execution context</td></tr>
<tr><td><span class="code-inline">#print(text)</span> writes while compiling</td><td><span class="code-inline">@print(...)</span> writes when the containing code executes</td></tr>
<tr><td>'#init { ... }' declares a module hook</td><td><span class="code-inline">@init(...)</span> initializes values or memory</td></tr>
<tr><td>'#drop { ... }' declares a module hook</td><td><span class="code-inline">@drop(...)</span> drops values or memory</td></tr>
</table>
<p>The pairs are related, not symmetrical. The compile-time diagnostics <span class="code-inline">#print</span>, <span class="code-inline">#assert</span>, <span class="code-inline">#error</span> and <span class="code-inline">#warning</span> each take exactly <b>one</b> compile-time expression, so several parts are joined with the <span class="code-inline">++</span> concatenation operator. Their intrinsic counterparts follow ordinary call rules, and <span class="code-inline">@print</span> is variadic:</p>
<div class="code-block"><span class="SCde"><span class="SCmp">#print</span>(<span class="SStr">"kind: "</span> ++ <span class="SItr">#nameof</span>(<span class="SItr">#typeof</span>(value)))     <span class="SCmt">// one expression, joined with '++'</span>
<span class="SItr">@print</span>(<span class="SStr">"kind: "</span>, name, <span class="SStr">"\n"</span>)                    <span class="SCmt">// variadic at runtime</span>
</span></div>
<p>Inside <span class="code-inline">#run</span>, an <span class="code-inline">@</span> intrinsic executes during compilation because the containing code does. In an ordinary function, the same intrinsic becomes generated runtime behavior.</p>
<h3 id="The_Four_Modifier_Families">The Four Modifier Families</h3>
<p>The modifiers are not one list. Each one belongs to exactly one of four families, and the family says what it annotates.</p>
<h3 id="Type_Qualifiers">Type Qualifiers</h3>
<p><span class="code-inline">#null</span> is part of the type itself and takes part in conversions. The bare <span class="code-inline">null</span> token is a value:</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> missing: <span class="SItr">#null</span> *<span class="STpe">s32</span> = <span class="SKwd">null</span>
    <span class="SItr">@assert</span>(missing == <span class="SKwd">null</span>)
}

</span></div>
<h3 id="Passing_Modes">Passing Modes</h3>
<p><span class="code-inline">#move</span> and <span class="code-inline">#fwd</span> in a parameter position are part of the signature: they select how an argument reaches the callee. They belong to the type, so they cannot be attributes.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">take</span>(value: <span class="SItr">#move</span> <span class="SCst">Buffer</span>) { ... }
</span></div>
<h3 id="Operation_Modifiers">Operation Modifiers</h3>
<p>These change one operation rather than producing a value:</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> byte = <span class="SNum">255</span>'<span class="STpe">u8</span>
    byte += <span class="SItr">#wrap</span> <span class="SNum">1</span>'<span class="STpe">u8</span>
    <span class="SItr">@assert</span>(byte == <span class="SNum">0</span>)

    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(<span class="SNum">255</span>'<span class="STpe">u8</span> + <span class="SItr">#prom</span> <span class="SNum">1</span>'<span class="STpe">u8</span>) == <span class="STpe">u32</span>)

    <span class="SKwd">let</span> bits = <span class="SKwd">cast</span> <span class="SItr">#bit</span> (<span class="STpe">u32</span>) <span class="SNum">1.0</span>'<span class="STpe">f32</span>
    <span class="SItr">@assert</span>(bits == <span class="SNum">0x3F800000</span>)
}

</span></div>
<p><span class="code-inline">#bit</span> and <span class="code-inline">#unconst</span> select a variant of the <span class="code-inline">cast</span> they sit in; neither is a type qualifier, and neither can be written in a type position. <span class="code-inline">#unconst</span> removes a const qualifier only where the language permits that explicit escape.</p>
<p><span class="code-inline">#nodrop</span>, <span class="code-inline">#move</span>, and <span class="code-inline">#relocate</span> modify one assignment or one initializer.</p>
<p><span class="code-inline">#raw</span> modifies how the compiler reads the string literal that follows: its content is taken verbatim, with no escape sequence recognized.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">let</span> pattern = <span class="SItr">#raw</span> <span class="SStr">"(\d+)x(\d+)"</span>
<span class="SKwd">let</span> payload = <span class="SItr">#raw</span> <span class="SStr">""</span><span class="SStr">"{"</span>key<span class="SStr">": "</span>value<span class="SStr">"}"</span><span class="SStr">""</span>
</span></div>
<h3 id="Statement_Selectors">Statement Selectors</h3>
<p>These choose a variant of the statement they follow. A statement has no symbol, so a selector is the only form available — and this is the family a user extends with a custom sharp selector such as 'for #Pairs'.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> expected = <span class="SNum">2</span>
    <span class="SLgc">for</span> <span class="SItr">#reverse</span> <span class="SNum">3</span>
    {
        <span class="SItr">@assert</span>(<span class="SItr">@index</span> == expected)
        expected -= <span class="SNum">1</span>
    }

    <span class="SKwd">enum</span> <span class="SCst">Direction</span> { <span class="SCst">Up</span>, <span class="SCst">Down</span> }
    <span class="SKwd">let</span> direction = <span class="SCst">Direction</span>.<span class="SCst">Up</span>

    <span class="SLgc">switch</span> <span class="SItr">#complete</span> direction
    {
    <span class="SLgc">case</span> .<span class="SCst">Up</span>:   <span class="SItr">@assert</span>(<span class="SKwd">true</span>)
    <span class="SLgc">case</span> .<span class="SCst">Down</span>: <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    }
}

</span></div>
<p>'defer #fail' and 'defer #nofail' select which exit path runs the deferred statement. They are opposite exit paths and cannot be combined.</p>
<h3 id="Where_Modifiers_Go">Where Modifiers Go</h3>
<p>A modifier is always written <b>immediately after the keyword it modifies</b>, never after the operand: 'switch #complete value', not 'switch value #complete'. The same holds for <span class="code-inline">cast</span>, <span class="code-inline">for</span>, <span class="code-inline">defer</span>, and an assignment operator.</p>
<p>A directive is the opposite: it comes <b>first</b>, because it introduces the construct instead of refining one. '#static switch' is not a <span class="code-inline">switch</span> carrying a flag; it is a distinct compile-time construct that happens to reuse the <span class="code-inline">switch</span> spelling. That is why <span class="code-inline">#static</span> leads and <span class="code-inline">#complete</span> follows:</p>
<div class="code-block"><span class="SCde"><span class="SCmp">#static</span> <span class="SLgc">switch</span> <span class="SItr">#complete</span> value
</span></div>
<p>Several modifiers on the same construct form a <b>set</b>, so their order carries no meaning and a repeat is rejected:</p>
<div class="code-block"><span class="SCde">a = <span class="SItr">#nodrop</span> <span class="SItr">#move</span> b     <span class="SCmt">// same as '#move #nodrop'</span>
<span class="SKwd">let</span> bits = <span class="SKwd">cast</span> <span class="SItr">#bit</span> <span class="SItr">#unconst</span> (*<span class="STpe">s32</span>) p
</span></div>
<p>One ordering rule does exist: on <span class="code-inline">for</span>, a custom sharp selector comes <b>before</b> the modifiers, because the selector names which iteration hook is resolved.</p>
<div class="code-block"><span class="SCde"><span class="SLgc">for</span> <span class="SInv">#Pairs</span> <span class="SItr">#reverse</span> [right] <span class="SLgc">in</span> values     <span class="SCmt">// accepted</span>
<span class="SLgc">for</span> <span class="SItr">#reverse</span> <span class="SInv">#Pairs</span> [right] <span class="SLgc">in</span> values     <span class="SCmt">// rejected</span>
</span></div>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> a = <span class="SNum">250</span>'<span class="STpe">u8</span>

    <span class="SCmt">// Order between modifiers carries no meaning.</span>
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(a + <span class="SItr">#wrap</span> <span class="SItr">#prom</span> <span class="SNum">1</span>'<span class="STpe">u8</span>) == <span class="STpe">u32</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(a + <span class="SItr">#prom</span> <span class="SItr">#wrap</span> <span class="SNum">1</span>'<span class="STpe">u8</span>) == <span class="STpe">u32</span>)
}

</span></div>
<h3 id="Choosing_the_Narrowest_Scope">Choosing the Narrowest Scope</h3>
<p><span class="code-inline">#wrap</span> opts one arithmetic operation into wrapping behavior. Broader runtime guard policy uses <span class="code-inline">Swag.Safety</span> on a scope, and module defaults live in <span class="code-inline">BuildCfg</span>:</p>
<div class="code-block"><span class="SCde"><span class="SAtr">#[Swag.Safety(.Overflow, false)]</span>
{
    <span class="SCmt">// Overflow guards are disabled only in this lexical scope.</span>
}
</span></div>
<p>Both spellings are legitimate, and the rule above says which is which: <span class="code-inline">#wrap</span> annotates one operation, <span class="code-inline">Swag.Safety</span> annotates a scope. Use the narrowest one that expresses the intent. A local <span class="code-inline">#wrap</span> documents one deliberate wrap more clearly than disabling overflow checks for a file.</p>
<h3 id="Contextual_Keywords_Are_Different">Contextual Keywords Are Different</h3>
<p>Bare <span class="code-inline">as</span> and <span class="code-inline">is</span> are grammar keywords used by matching constructs. <span class="code-inline">@as</span> and <span class="code-inline">@is</span> are intrinsics and can appear in expressions. The spelling is related, but the parser and type checker give the two forms distinct roles.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> boxed: <span class="STpe">any</span> = <span class="SStr">"text"</span>

    <span class="SLgc">switch</span> boxed
    {
    <span class="SLgc">case</span> <span class="STpe">string</span> <span class="SLgc">as</span> text: <span class="SItr">@assert</span>(text == <span class="SStr">"text"</span>)
    <span class="SLgc">default</span>:             <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    }
}

</span></div>
<h3 id="_002_009_visibility_and_exports_swg">Visibility and Exports</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Visibility">Visibility</h3>
<p>Top-level declarations use three visibility levels:</p>
<table class="table-markdown">
<tr><th>Modifier</th><th>Visible from the same file</th><th>Other files in the module</th><th>Importing modules</th></tr>
<tr><td><span class="code-inline">private</span></td><td>yes</td><td>no</td><td>no</td></tr>
<tr><td><span class="code-inline">internal</span></td><td>yes</td><td>yes</td><td>no</td></tr>
<tr><td><span class="code-inline">public</span></td><td>yes</td><td>yes</td><td>yes</td></tr>
</table>
<p><span class="code-inline">internal</span> is the default. Use <span class="code-inline">public</span> deliberately for the supported module API and <span class="code-inline">private</span> for file-local implementation details.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">private</span> <span class="SKwd">const</span> <span class="SCst">VisibilityFileLocal</span> = <span class="SNum">10</span>
<span class="SKwd">internal</span> <span class="SKwd">const</span> <span class="SCst">VisibilityModuleLocal</span> = <span class="SNum">20</span>

<span class="SFct">#test</span>
{
    <span class="SItr">@assert</span>(<span class="SCst">VisibilityFileLocal</span> + <span class="SCst">VisibilityModuleLocal</span> == <span class="SNum">30</span>)
}

</span></div>
<h3 id="Applying_Visibility_to_a_Group_or_File">Applying Visibility to a Group or File</h3>
<p>An access block applies one modifier to several declarations:</p>
<div class="code-block"><span class="SCde"><span class="SKwd">public</span>
{
    <span class="SKwd">struct</span> <span class="SCst">Request</span>
    {
        id: <span class="STpe">u64</span>
    }

    <span class="SKwd">func</span> <span class="SFct">submit</span>(request: <span class="SCst">Request</span>)
}
</span></div>
<p><span class="code-inline">#global</span> changes the default for the rest of one source file. This reference starts files with '#global private' so examples cannot leak into a generated module API:</p>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>
</span></div>
<p>Visibility is independent of namespaces. A symbol can be public and qualified, or private and placed in a namespace for organization.</p>
<h3 id="Exporting_a_File_s_API">Exporting a File's API</h3>
<p>'#global export' is a fourth form. It sets the same access as '#global public', and additionally marks the file as one whose declarations belong to the generated module API. Only the file's first <span class="code-inline">#global</span> directive is read for that marking, so it belongs on the very first line. The standard modules open their public source files with it:</p>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> export
</span></div>
<p>Use '#global public' when a file is public inside the workspace, and '#global export' when its declarations are the module's published surface.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_002_010_module_lifecycle_swg">Module Lifecycle</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Module_Entry_Points_and_Hooks">Module Entry Points and Hooks</h3>
<p>Swag reserves <span class="code-inline">#</span>-prefixed functions for module lifecycle events. They are declarations, not ordinary functions, and the compiler invokes them at the appropriate phase.</p>
<table class="table-markdown">
<tr><th>Hook</th><th>Purpose</th></tr>
<tr><td><span class="code-inline">#init</span></td><td>Initialize module runtime state before entry points or tests</td></tr>
<tr><td><span class="code-inline">#premain</span></td><td>Run after all module initializers and before an executable's <span class="code-inline">#main</span></td></tr>
<tr><td><span class="code-inline">#main</span></td><td>Enter an executable module</td></tr>
<tr><td><span class="code-inline">#test</span></td><td>Declare a test executed by the <span class="code-inline">test</span> command</td></tr>
<tr><td><span class="code-inline">#drop</span></td><td>Release module state during shutdown</td></tr>
</table>
<h3 id="Initialization">Initialization</h3>
<p>A module may contain several <span class="code-inline">#init</span> hooks. Their relative order is unspecified, so each hook must establish its own invariants. Dependency modules initialize before modules that import them.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">var</span> <span class="SCst">ModuleLifecycleInitialized</span> = <span class="SKwd">false</span>

<span class="SFct">#init</span>
{
    <span class="SCst">ModuleLifecycleInitialized</span> = <span class="SKwd">true</span>
}

<span class="SFct">#test</span>
{
    <span class="SItr">@assert</span>(<span class="SCst">ModuleLifecycleInitialized</span>)
}

</span></div>
<h3 id="Executable_Entry">Executable Entry</h3>
<p>An executable has one <span class="code-inline">#main</span>. Command-line arguments are available through <span class="code-inline">@args</span>.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#main</span>
{
    <span class="SLgc">for</span> argument, [index] <span class="SLgc">in</span> <span class="SItr">@args</span>
        <span class="SItr">@print</span>(index, <span class="SStr">": "</span>, argument, <span class="SStr">"\n"</span>)
}
</span></div>
<p><span class="code-inline">#premain</span> is useful for application setup that must happen after every imported module has initialized but before <span class="code-inline">#main</span> begins.</p>
<h3 id="Shutdown">Shutdown</h3>
<p><span class="code-inline">#drop</span> hooks run when a module unloads. Use them to release resources acquired by <span class="code-inline">#init</span>. Multiple module drop hooks execute in the reverse order of their corresponding initialization sequence.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#drop</span>
{
    <span class="SCmt">// Close handles and release module-owned resources.</span>
}
</span></div>
<div class="blockquote blockquote-warning">
<div class="blockquote-title-block"><span class="blockquote-title">Warning</span></div>
<p>Do not confuse <span class="code-inline">#init</span> and <span class="code-inline">#drop</span> module hooks with the <span class="code-inline">@init</span> and <span class="code-inline">@drop</span> intrinsics. The hooks manage a module's lifetime; the intrinsics operate on values and memory regions.</p>
</div>
<div class="code-block"><span class="SCde">
</span></div>
<h2 id="_003_000_fundamentals_swg">Fundamentals</h2>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>
</span></div>
<p>This chapter establishes the value model: built-in scalar types, literals, strings, constants, variables, operators, conversions, and aliases. Later chapters build aggregates and generic abstractions from these rules.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_003_001_basic_types_swg">Basic Types</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Signed_Integers">Signed Integers</h3>
<p>Swag provides various signed integer types: <span class="code-inline">s8</span>, <span class="code-inline">s16</span>, <span class="code-inline">s32</span>, and <span class="code-inline">s64</span>. These types represent signed integers with different bit widths, allowing both positive and negative values within their respective ranges. Each type is designed for efficient integer operations at varying levels of precision.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> a: <span class="STpe">s8</span>  = -<span class="SNum">1</span>     <span class="SCmt">// 8-bit signed integer, range: -128 to 127</span>
    <span class="SKwd">let</span> b: <span class="STpe">s16</span> = -<span class="SNum">2</span>     <span class="SCmt">// 16-bit signed integer, range: -32,768 to 32,767</span>
    <span class="SKwd">let</span> c: <span class="STpe">s32</span> = -<span class="SNum">3</span>     <span class="SCmt">// 32-bit signed integer, range: -2^31 to 2^31-1</span>
    <span class="SKwd">let</span> d: <span class="STpe">s64</span> = -<span class="SNum">4</span>     <span class="SCmt">// 64-bit signed integer, range: -2^63 to 2^63-1</span>

    <span class="SItr">@assert</span>(a == -<span class="SNum">1</span>)
    <span class="SItr">@assert</span>(b == -<span class="SNum">2</span>)
    <span class="SItr">@assert</span>(c == -<span class="SNum">3</span>)
    <span class="SItr">@assert</span>(d == -<span class="SNum">4</span>)

    <span class="SItr">@assert</span>(<span class="SItr">#sizeof</span>(a) == <span class="SNum">1</span>)     <span class="SCmt">// 'a' is an 's8' â 1 byte</span>
    <span class="SItr">@assert</span>(<span class="SItr">#sizeof</span>(b) == <span class="SNum">2</span>)     <span class="SCmt">// 'b' is an 's16' â 2 bytes</span>
    <span class="SItr">@assert</span>(<span class="SItr">#sizeof</span>(c) == <span class="SNum">4</span>)     <span class="SCmt">// 'c' is an 's32' â 4 bytes</span>
    <span class="SItr">@assert</span>(<span class="SItr">#sizeof</span>(d) == <span class="SNum">8</span>)     <span class="SCmt">// 'd' is an 's64' â 8 bytes</span>
}

</span></div>
<h3 id="Unsigned_Integers">Unsigned Integers</h3>
<p>Swag also supports unsigned integer types: <span class="code-inline">u8</span>, <span class="code-inline">u16</span>, <span class="code-inline">u32</span>, and <span class="code-inline">u64</span>. These types can only represent non-negative values, making them ideal for counting, indexing, and other operations where negative numbers are not applicable.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> a: <span class="STpe">u8</span>  = <span class="SNum">1</span>     <span class="SCmt">// 8-bit unsigned integer, range: 0 to 255</span>
    <span class="SKwd">let</span> b: <span class="STpe">u16</span> = <span class="SNum">2</span>     <span class="SCmt">// 16-bit unsigned integer, range: 0 to 65,535</span>
    <span class="SKwd">let</span> c: <span class="STpe">u32</span> = <span class="SNum">3</span>     <span class="SCmt">// 32-bit unsigned integer, range: 0 to 2^32-1</span>
    <span class="SKwd">let</span> d: <span class="STpe">u64</span> = <span class="SNum">4</span>     <span class="SCmt">// 64-bit unsigned integer, range: 0 to 2^64-1</span>

    <span class="SItr">@assert</span>(a == <span class="SNum">1</span>)
    <span class="SItr">@assert</span>(b == <span class="SNum">2</span>)
    <span class="SItr">@assert</span>(c == <span class="SNum">3</span>)
    <span class="SItr">@assert</span>(d == <span class="SNum">4</span>)

    <span class="SItr">@assert</span>(<span class="SItr">#sizeof</span>(a) == <span class="SNum">1</span>)     <span class="SCmt">// 'a' is a 'u8' â 1 byte</span>
    <span class="SItr">@assert</span>(<span class="SItr">#sizeof</span>(b) == <span class="SNum">2</span>)     <span class="SCmt">// 'b' is a 'u16' â 2 bytes</span>
    <span class="SItr">@assert</span>(<span class="SItr">#sizeof</span>(c) == <span class="SNum">4</span>)     <span class="SCmt">// 'c' is a 'u32' â 4 bytes</span>
    <span class="SItr">@assert</span>(<span class="SItr">#sizeof</span>(d) == <span class="SNum">8</span>)     <span class="SCmt">// 'd' is a 'u64' â 8 bytes</span>
}

</span></div>
<h3 id="Floating-Point_Types">Floating-Point Types</h3>
<p>Swag supports floating-point types <span class="code-inline">f32</span> and <span class="code-inline">f64</span>. These represent single- and double-precision floating-point numbers, suitable for calculations requiring fractional values or higher precision.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> a: <span class="STpe">f32</span> = <span class="SNum">3.14</span>        <span class="SCmt">// 32-bit float (single precision)</span>
    <span class="SKwd">let</span> b: <span class="STpe">f64</span> = <span class="SNum">3.14159</span>     <span class="SCmt">// 64-bit float (double precision)</span>

    <span class="SItr">@assert</span>(a == <span class="SNum">3.14</span>)
    <span class="SItr">@assert</span>(b == <span class="SNum">3.14159</span>)

    <span class="SItr">@assert</span>(<span class="SItr">#sizeof</span>(a) == <span class="SNum">4</span>)     <span class="SCmt">// 'a' is an 'f32' â 4 bytes</span>
    <span class="SItr">@assert</span>(<span class="SItr">#sizeof</span>(b) == <span class="SNum">8</span>)     <span class="SCmt">// 'b' is an 'f64' â 8 bytes</span>
}

</span></div>
<h3 id="Boolean_Type">Boolean Type</h3>
<p>The boolean type <span class="code-inline">bool</span> represents logical true or false values. In Swag, a boolean occupies 1 byte of memory.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> a: <span class="STpe">bool</span> = <span class="SKwd">true</span>
    <span class="SKwd">let</span> b: <span class="STpe">bool</span> = <span class="SKwd">false</span>

    <span class="SItr">@assert</span>(a == <span class="SKwd">true</span>)
    <span class="SItr">@assert</span>(b == <span class="SKwd">false</span>)

    <span class="SItr">@assert</span>(<span class="SItr">#sizeof</span>(a) == <span class="SNum">1</span>)     <span class="SCmt">// 'bool' â 1 byte</span>
    <span class="SItr">@assert</span>(<span class="SItr">#sizeof</span>(b) == <span class="SNum">1</span>)
}

</span></div>
<h3 id="String_Type">String Type</h3>
<p>The <span class="code-inline">string</span> type represents text. Strings in Swag are UTF-8 encoded and stored as two 64-bit values: one for the data pointer and one for the length in bytes. This structure ensures efficient text manipulation and full Unicode compatibility.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> a: <span class="STpe">string</span> = <span class="SStr">"string æ¯"</span>     <span class="SCmt">// UTF-8 encoded string</span>

    <span class="SItr">@assert</span>(a == <span class="SStr">"string æ¯"</span>)
    <span class="SItr">@assert</span>(<span class="SItr">#sizeof</span>(a) == <span class="SNum">2</span> * <span class="SItr">#sizeof</span>(<span class="SItr">#null</span> *<span class="STpe">void</span>))     <span class="SCmt">// Pointer + length</span>
}

</span></div>
<h3 id="Rune_Type">Rune Type</h3>
<p>The <span class="code-inline">rune</span> type represents a 32-bit Unicode code point. It stores a single Unicode character and is ideal for per-character text operations across languages.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> a: <span class="STpe">rune</span> = '是'     <span class="SCmt">// Single Unicode code point</span>

    <span class="SItr">@assert</span>(a == '是')
    <span class="SItr">@assert</span>(<span class="SItr">#sizeof</span>(a) == <span class="SNum">4</span>)     <span class="SCmt">// 'rune' â 4 bytes (32 bits)</span>
}

</span></div>
<h3 id="Type_Reflection">Type Reflection</h3>
<p>Swag supports <b>type reflection</b> at both <b>compile time</b> and <b>runtime</b>. This allows inspection and manipulation of types dynamically, enabling powerful and introspective programming techniques.</p>
<p>Further details about type reflection are explored in later sections.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="Type_Creation_with___decltype_">Type Creation with <span class="code-inline">#decltype</span></h3>
<p>You can use <span class="code-inline">#decltype</span> to create a type based on an existing expression. This is useful for inferring or mirroring the type of another variable dynamically, improving reusability and reducing redundancy.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> a               = <span class="SNum">0</span>     <span class="SCmt">// Type of 'a' inferred as 's32'</span>
    <span class="SKwd">let</span> b: <span class="SItr">#decltype</span>(a) = <span class="SNum">1</span>     <span class="SCmt">// 'b' declared with same type as 'a'</span>

    <span class="SItr">@assert</span>(<span class="SItr">#typeof</span>(a) == <span class="SItr">#typeof</span>(b))
    <span class="SItr">@assert</span>(<span class="SItr">#typeof</span>(a) == <span class="STpe">s32</span>)

    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(a) == <span class="SItr">#typeof</span>(b))
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(a) == <span class="STpe">s32</span>)
}

</span></div>
<h3 id="_003_002_number_literals_swg">Number Literals</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Number_Representations">Number Representations</h3>
<p>Integers can be written in multiple formats: <i>decimal</i>, <i>hexadecimal</i>, or <i>binary</i>. These representations allow you to express numbers in the format that best fits your use case or domain requirements.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">const</span> a: <span class="STpe">u32</span> = <span class="SNum">123456</span>         <span class="SCmt">// Decimal format</span>
    <span class="SKwd">const</span> b: <span class="STpe">u32</span> = <span class="SNum">0xFFFF</span>         <span class="SCmt">// Hexadecimal, prefixed with '0x' (represents 65535)</span>
    <span class="SKwd">const</span> c: <span class="STpe">u32</span> = <span class="SNum">0b00001111</span>     <span class="SCmt">// Binary, prefixed with '0b' (represents 15)</span>

    <span class="SItr">@assert</span>(a == <span class="SNum">123456</span>)
    <span class="SItr">@assert</span>(b == <span class="SNum">65535</span>)
    <span class="SItr">@assert</span>(c == <span class="SNum">15</span>)
}

</span></div>
<h3 id="Digit_Separators">Digit Separators</h3>
<p>Numeric literals can use the underscore (<span class="code-inline">_</span>) as a digit separator for better readability. Separators do not affect the numeric value.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">const</span> a: <span class="STpe">u32</span> = <span class="SNum">123_456</span>         <span class="SCmt">// Decimal with separators</span>
    <span class="SKwd">const</span> b: <span class="STpe">u32</span> = <span class="SNum">0xF_F_F_F</span>       <span class="SCmt">// Hexadecimal with separators</span>
    <span class="SKwd">const</span> c: <span class="STpe">u32</span> = <span class="SNum">0b0000_1111</span>     <span class="SCmt">// Binary with separators</span>

    <span class="SItr">@assert</span>(a == <span class="SNum">123456</span>)
    <span class="SItr">@assert</span>(b == <span class="SNum">65535</span>)
    <span class="SItr">@assert</span>(c == <span class="SNum">15</span>)
}

</span></div>
<h3 id="Default_Integer_Types">Default Integer Types</h3>
<p>In Swag, hexadecimal or binary literals default to type <span class="code-inline">u32</span> if the value fits within 32 bits. If the literal exceeds 32 bits, it is automatically inferred as <span class="code-inline">u64</span>.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">const</span> a = <span class="SNum">0xFF</span>     <span class="SCmt">// Fits in 32 bits â inferred as 'u32'</span>
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(a) == <span class="STpe">u32</span>)

    <span class="SKwd">const</span> b = <span class="SNum">0xF_FFFFF_FFFFFF</span>     <span class="SCmt">// Exceeds 32 bits â inferred as 'u64'</span>
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(b) == <span class="STpe">u64</span>)

    <span class="SKwd">const</span> c = <span class="SNum">0b00000001</span>     <span class="SCmt">// Within 32 bits â inferred as 'u32'</span>
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(c) == <span class="STpe">u32</span>)

    <span class="SKwd">const</span> d = <span class="SNum">0b00000001_00000001_00000001_00000001_00000001</span>     <span class="SCmt">// Exceeds 32 bits â 'u64'</span>
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(d) == <span class="STpe">u64</span>)
}

</span></div>
<h3 id="Booleans">Booleans</h3>
<p>A <span class="code-inline">bool</span> type can hold either <span class="code-inline">true</span> or <span class="code-inline">false</span>. Since constants are known at compile time, you can use <span class="code-inline">#assert</span> to verify their values during compilation.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">const</span> a = <span class="SKwd">true</span>
    <span class="SCmp">#assert</span>(a == <span class="SKwd">true</span>)
    <span class="SKwd">const</span> b, c = <span class="SKwd">false</span>
    <span class="SCmp">#assert</span>(b == <span class="SKwd">false</span>)
    <span class="SCmp">#assert</span>(c == <span class="SKwd">false</span>)
}

</span></div>
<h3 id="Floating-Point_Values">Floating-Point Values</h3>
<p>Floating-point literals use standard C-style notation. This makes them familiar and easy to read for developers coming from C or C++ backgrounds.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> a = <span class="SNum">1.5</span>
    <span class="SItr">@assert</span>(a == <span class="SNum">1.5</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(a) == <span class="STpe">f32</span>)     <span class="SCmt">// Default float type is 'f32'</span>

    <span class="SKwd">let</span> b = <span class="SNum">0.11</span>
    <span class="SItr">@assert</span>(b == <span class="SNum">0.11</span>)

    <span class="SKwd">let</span> c = <span class="SNum">15e2</span>
    <span class="SItr">@assert</span>(c == <span class="SNum">15e2</span>)     <span class="SCmt">// Equivalent to 1500</span>

    <span class="SKwd">let</span> d = <span class="SNum">15e+2</span>
    <span class="SItr">@assert</span>(d == <span class="SNum">15e2</span>)

    <span class="SKwd">let</span> e = -<span class="SNum">1e-1</span>
    <span class="SItr">@assert</span>(e == -<span class="SNum">0.1</span>)
}

</span></div>
<h3 id="Default_Floating-Point_Type">Default Floating-Point Type</h3>
<p>By default, floating-point literals are of type <span class="code-inline">f32</span>. This differs from C and C++, where floating-point literals default to <span class="code-inline">double</span> (<span class="code-inline">f64</span>).</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> a = <span class="SNum">1.5</span>
    <span class="SItr">@assert</span>(a == <span class="SNum">1.5</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(a) == <span class="STpe">f32</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(a) != <span class="STpe">f64</span>)
}

</span></div>
<h3 id="Literal_Suffix">Literal Suffix</h3>
<p>You can specify the type of a literal explicitly by adding a <b>suffix</b> to it. This is useful when a specific type is required, such as <span class="code-inline">f64</span> or <span class="code-inline">u8</span>.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> a = <span class="SNum">1.5</span>'<span class="STpe">f64</span>     <span class="SCmt">// Explicitly declare 'a' as 'f64'</span>
    <span class="SItr">@assert</span>(a == <span class="SNum">1.5</span>)
    <span class="SItr">@assert</span>(a == <span class="SNum">1.5</span>'<span class="STpe">f64</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(a) == <span class="STpe">f64</span>)

    <span class="SKwd">let</span> b = <span class="SNum">10</span>'<span class="STpe">u8</span>     <span class="SCmt">// Declare 'b' as 'u8'</span>
    <span class="SItr">@assert</span>(b == <span class="SNum">10</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(b) == <span class="STpe">u8</span>)

    <span class="SKwd">let</span> c = <span class="SNum">1</span>'<span class="STpe">u32</span>     <span class="SCmt">// Explicitly typed as 'u32'</span>
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(c) == <span class="STpe">u32</span>)
}

</span></div>
<h3 id="_003_003_string_swg">String</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="UTF-8_Encoding">UTF-8 Encoding</h3>
<p>Swag uses UTF-8 encoding for strings, allowing representation of characters from virtually all languages and symbol sets.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="String_Comparison">String Comparison</h3>
<p>Strings can be compared directly for equality using the <span class="code-inline">==</span> operator.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">const</span> a = <span class="SStr">"this is a Chinese character: æ¯"</span>
    <span class="SCmp">#assert</span>(a == <span class="SStr">"this is a Chinese character: æ¯"</span>)

    <span class="SKwd">const</span> b = <span class="SStr">"these are some Cyrillic characters: ÓÐ"</span>
    <span class="SCmp">#assert</span>(b == <span class="SStr">"these are some Cyrillic characters: ÓÐ"</span>)
}

</span></div>
<h3 id="The__rune__Type">The <span class="code-inline">rune</span> Type</h3>
<p>A <span class="code-inline">rune</span> represents a Unicode code point and is stored as a 32-bit value, ensuring it can accommodate any Unicode character.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">const</span> a: <span class="STpe">rune</span> = '是'
    <span class="SCmp">#assert</span>(a == '是')
    <span class="SCmp">#assert</span>(<span class="SItr">#sizeof</span>(a) == <span class="SItr">#sizeof</span>(<span class="STpe">u32</span>))
}

</span></div>
<div class="blockquote blockquote-warning">
<div class="blockquote-title-block"><span class="blockquote-title">Warning</span></div>
<p>Direct indexing of a string to retrieve a <span class="code-inline">rune</span> is not supported, except for ASCII strings. Swag avoids the runtime overhead of UTF-8 decoding. The <span class="code-inline">Std.Core</span> module provides utilities for working with UTF-8 strings.</p>
</div>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="String_Indexing">String Indexing</h3>
<p>When indexing a string, Swag returns a byte (<span class="code-inline">u8</span>), not a <span class="code-inline">rune</span>. This reflects the underlying UTF-8 encoding.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">const</span> a = <span class="SStr">"this is a Chinese character: æ¯"</span>

    <span class="SCmt">// Retrieve the first byte ('t')</span>
    <span class="SKwd">const</span> b = a[<span class="SNum">0</span>]
    <span class="SCmp">#assert</span>(b == '<span class="SFct">t</span>')
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(b) == <span class="SItr">#typeof</span>(<span class="STpe">u8</span>))

    <span class="SCmt">// Multibyte UTF-8 affects indexing</span>
    <span class="SKwd">const</span> c = <span class="SStr">"æ¯Xæ¯"</span>
    <span class="SCmp">#assert</span>(c[<span class="SNum">1</span>] != '<span class="SFct">X</span>')
}

</span></div>
<h3 id="String_Concatenation">String Concatenation</h3>
<p>Swag allows compile-time concatenation of strings and other values using the <span class="code-inline">++</span> operator.</p>
<div class="blockquote blockquote-warning">
<div class="blockquote-title-block"><span class="blockquote-title">Warning</span></div>
<p><span class="code-inline">++</span> is a <b>compile-time</b> operator: every operand must be a constant expression. The <span class="code-inline">let</span> bindings below hold a value the compiler already folded, not a runtime concatenation. Two runtime strings cannot be joined by an operator at all — <span class="code-inline">+</span> is not defined on <span class="code-inline">string</span>, and <span class="code-inline">++</span> reports that the expression needs a compile-time value. Build runtime text with <span class="code-inline">Std.Core</span> (<span class="code-inline">String</span>, <span class="code-inline">ConcatBuffer</span>, <span class="code-inline">Format</span>) instead.</p>
</div>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">const</span> a = <span class="SStr">"the devil's number is "</span> ++ <span class="SNum">666</span>
    <span class="SCmp">#assert</span>(a == <span class="SStr">"the devil's number is 666"</span>)

    <span class="SKwd">const</span> b = <span class="SNum">666</span>
    <span class="SKwd">let</span> c = <span class="SStr">"the devil's number is not "</span> ++ (b + <span class="SNum">1</span>) ++ <span class="SStr">"!"</span>
    <span class="SItr">@assert</span>(c == <span class="SStr">"the devil's number is not 667!"</span>)

    <span class="SKwd">let</span> d = <span class="SStr">"there are "</span> ++ <span class="SNum">4</span> ++ <span class="SStr">" apples in "</span> ++ (<span class="SNum">2</span> * <span class="SNum">2</span>) ++ <span class="SStr">" baskets"</span>
    <span class="SItr">@assert</span>(d == <span class="SStr">"there are 4 apples in 4 baskets"</span>)
}

</span></div>
<h3 id="Null_Strings">Null Strings</h3>
<p>A string can be <span class="code-inline">null</span> if it has not been initialized. This allows checking whether a string has been assigned a value.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> a: <span class="SItr">#null</span> <span class="STpe">string</span>
    <span class="SItr">@assert</span>(a == <span class="SKwd">null</span>)
    a = <span class="SStr">"not null"</span>
    <span class="SItr">@assert</span>(a != <span class="SKwd">null</span>)
    a = <span class="SKwd">null</span>
    <span class="SItr">@assert</span>(a == <span class="SKwd">null</span>)
}

</span></div>
<h3 id="Character_Literals">Character Literals</h3>
<p>Character literals are enclosed in quotes and can represent any Unicode character, not just ASCII.</p>
<div class="blockquote blockquote-note">
<div class="blockquote-title-block"><span class="blockquote-title">Note</span></div>
<p>The quote is shared with the suffix and generic-argument syntax, so the lexer reads it from what comes before: right after an identifier or a literal it opens a suffix or a generic argument list, anywhere else it opens a character literal. Only meaningful tokens count, so blanks and comments never change the reading and <span class="code-inline">5</span>s32' and '5 <span class="code-inline">s32</span> are the same suffixed literal.</p>
</div>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> char0 = '<span class="SFct">a</span>'
    <span class="SKwd">let</span> char1 = '我'
    <span class="SKwd">let</span> value = <span class="SNum">5</span>'<span class="STpe">s32</span>     <span class="SCmt">// Type suffix example</span>

    <span class="SCmt">// The same literal, with the blank the lexer ignores.</span>
    <span class="SKwd">let</span> spaced = <span class="SNum">5</span> '<span class="STpe">s32</span>
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(spaced) == <span class="STpe">s32</span>)
    <span class="SItr">@assert</span>(spaced == value)
}

</span></div>
<h3 id="Default_Type_of_Character_Literals">Default Type of Character Literals</h3>
<p>A character literal initially has an adaptable character-literal type. Its context can select any integer type or <span class="code-inline">rune</span> when the value fits the target type.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    {
        <span class="SKwd">let</span> a: <span class="STpe">u8</span>   = '<span class="SFct">a</span>'
        <span class="SKwd">let</span> b: <span class="STpe">u16</span>  = '<span class="SFct">a</span>'
        <span class="SKwd">let</span> c: <span class="STpe">u32</span>  = '我'
        <span class="SKwd">let</span> d: <span class="STpe">u64</span>  = '我'
        <span class="SKwd">let</span> e: <span class="STpe">rune</span> = '我'
    }

    {
        <span class="SKwd">let</span> a: <span class="STpe">s8</span>  = '<span class="SFct">a</span>'
        <span class="SKwd">let</span> b: <span class="STpe">s16</span> = '<span class="SFct">a</span>'
        <span class="SKwd">let</span> c: <span class="STpe">s32</span> = '我'
        <span class="SKwd">let</span> d: <span class="STpe">s64</span> = '我'
    }
}

</span></div>
<h3 id="Specifying_Character_Literal_Types">Specifying Character Literal Types</h3>
<p>Character literals remain adaptable until their context selects a concrete type. To select one explicitly, place an unsigned integer type or <span class="code-inline">rune</span> directly after the closing quote. The literal is already closed by that quote, so it is the quote that separates the literal from its suffix and the suffix follows it immediately.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">let</span> letter = '<span class="SNum">0</span>'<span class="STpe">u8</span>      <span class="SCmt">// a 'u8'</span>
<span class="SKwd">let</span> space  = ' '<span class="STpe">u32</span>     <span class="SCmt">// the literal is a space, the suffix still follows the quote</span>
</span></div>
<div class="blockquote blockquote-note">
<div class="blockquote-title-block"><span class="blockquote-title">Note</span></div>
<p>A second quote before the suffix ("<span class="code-inline">0</span>'u8") was an earlier spelling and is now reported as an error. Remove it: the closing quote is the separator.</p>
</div>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> a = '<span class="SNum">0</span>'<span class="STpe">u8</span>
    <span class="SItr">@assert</span>(a == <span class="SNum">48</span>)
    <span class="SItr">@assert</span>(<span class="SItr">#typeof</span>(a) == <span class="STpe">u8</span>)

    <span class="SKwd">let</span> b = '<span class="SNum">1</span>'<span class="STpe">u16</span>
    <span class="SItr">@assert</span>(b == <span class="SNum">49</span>)
    <span class="SItr">@assert</span>(<span class="SItr">#typeof</span>(b) == <span class="STpe">u16</span>)

    <span class="SKwd">let</span> c = '<span class="SNum">2</span>'<span class="STpe">u32</span>
    <span class="SItr">@assert</span>(c == <span class="SNum">50</span>)
    <span class="SItr">@assert</span>(<span class="SItr">#typeof</span>(c) == <span class="STpe">u32</span>)

    <span class="SKwd">let</span> d = '<span class="SNum">3</span>'<span class="STpe">u64</span>
    <span class="SItr">@assert</span>(d == <span class="SNum">51</span>)
    <span class="SItr">@assert</span>(<span class="SItr">#typeof</span>(d) == <span class="STpe">u64</span>)

    <span class="SKwd">let</span> e = '<span class="SNum">4</span>'<span class="STpe">rune</span>
    <span class="SItr">@assert</span>(e == <span class="SNum">52</span>)
    <span class="SItr">@assert</span>(<span class="SItr">#typeof</span>(e) == <span class="STpe">rune</span>)

    <span class="SCmt">// The literal itself can be a space: the closing quote still ends it.</span>
    <span class="SKwd">let</span> f = ' '<span class="STpe">u32</span>
    <span class="SItr">@assert</span>(f == <span class="SNum">32</span>)
    <span class="SItr">@assert</span>(<span class="SItr">#typeof</span>(f) == <span class="STpe">u32</span>)
}

</span></div>
<h3 id="Escape_Sequences">Escape Sequences</h3>
<p>Swag supports escape sequences in strings and character literals to represent special characters.</p>
<div class="code-block"><span class="SCde">
</span></div>
<p>An escape sequence starts with a backslash (<span class="code-inline">\</span>) followed by a specific character.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">const</span> a = <span class="SStr">"this is ASCII code 0x00:   \0"</span>
    <span class="SKwd">const</span> b = <span class="SStr">"this is ASCII code 0x07:   \a"</span>
    <span class="SKwd">const</span> c = <span class="SStr">"this is ASCII code 0x08:   \b"</span>
    <span class="SKwd">const</span> d = <span class="SStr">"this is ASCII code 0x09:   \t"</span>
    <span class="SKwd">const</span> e = <span class="SStr">"this is ASCII code 0x0A:   \n"</span>
    <span class="SKwd">const</span> f = <span class="SStr">"this is ASCII code 0x0B:   \v"</span>
    <span class="SKwd">const</span> g = <span class="SStr">"this is ASCII code 0x0C:   \f"</span>
    <span class="SKwd">const</span> h = <span class="SStr">"this is ASCII code 0x0D:   \r"</span>
    <span class="SKwd">const</span> i = <span class="SStr">"this is ASCII code 0x22:   \""</span>
    <span class="SKwd">const</span> j = <span class="SStr">"this is ASCII code 0x27:   \'"</span>
    <span class="SKwd">const</span> k = <span class="SStr">"this is ASCII code 0x5C:   \\"</span>
}

</span></div>
<h3 id="ASCII_and_Unicode_Escape_Sequences">ASCII and Unicode Escape Sequences</h3>
<p>Escape sequences can represent characters via their ASCII or Unicode values.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    {
        <span class="SKwd">const</span> a = <span class="SStr">"\x26"</span>
        <span class="SKwd">const</span> b = <span class="SStr">"\u2626"</span>
        <span class="SKwd">const</span> c = <span class="SStr">"\U00101234"</span>
    }

    {
        <span class="SKwd">const</span> d = <span class="SStr">"\u2F46\u2F46"</span>
        <span class="SCmp">#assert</span>(d == <span class="SStr">"â½â½"</span>)

        <span class="SKwd">const</span> e = '\<span class="SFct">u2F46</span>'
        <span class="SCmp">#assert</span>(e == '⽆')
    }
}

</span></div>
<h3 id="Raw_Strings">Raw Strings</h3>
<p>A raw string is one where escape sequences are not processed. This is useful when working with many backslashes or special symbols.</p>
<p>The <span class="code-inline">#raw</span> modifier applies to the string literal that follows, so a raw string uses the ordinary delimiters: '#raw "..."' on one line, and '#raw """..."""' when the text itself contains a quote. The delimiter is what ends the literal, so a raw string cannot end with a quote: keep the text going past it, or use an ordinary string with escapes.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">const</span> a = <span class="SItr">#raw</span> <span class="SStr">"\u2F46"</span>     <span class="SCmt">// Raw string containing a Unicode escape</span>
    <span class="SCmp">#assert</span>(a != <span class="SStr">"â½"</span>)
    <span class="SCmp">#assert</span>(a == <span class="SItr">#raw</span> <span class="SStr">"\u2F46"</span>)
}

</span></div>
<p>Equivalent strings can be written using escape sequences or raw notation.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">const</span> a = <span class="SStr">"\\hello \\world"</span>
    <span class="SKwd">const</span> b = <span class="SItr">#raw</span> <span class="SStr">"\hello \world"</span>
    <span class="SCmp">#assert</span>(a == b)
}

</span></div>
<h3 id="Multiline_Raw_Strings">Multiline Raw Strings</h3>
<p>A raw string spans several lines with the <span class="code-inline">"""</span> delimiters. Leading spaces up to the opening delimiter column are removed from each line, exactly as for an ordinary multiline string: re-indentation is layout, not escaping.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">const</span> a = <span class="SItr">#raw</span> <span class="SStr">""</span><span class="SStr">"this is
                a
                string
                "</span><span class="SStr">""</span>
}

</span></div>
<h3 id="Multiline_Strings">Multiline Strings</h3>
<p>Multiline strings start and end with <span class="code-inline">"""</span>. Unlike raw strings, escape sequences are still processed.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">const</span> a = <span class="SStr">""</span><span class="SStr">"this is
                 a
                 string
                 "</span><span class="SStr">""</span>
}

</span></div>
<p>In multiline or raw strings, ending a line with <span class="code-inline">\</span> prevents the following end-of-line from being included.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">const</span> a = <span class="SStr">""</span><span class="SStr">"\
              this is
              a
              string
              "</span><span class="SStr">""</span>
}

</span></div>
<h3 id="The___stringof__and___nameof__Intrinsics">The <span class="code-inline">#stringof</span> and <span class="code-inline">#nameof</span> Intrinsics</h3>
<p>The <span class="code-inline">#stringof</span> intrinsic returns the string representation of a constant expression at compile time.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">const</span> <span class="SCst">X</span> = <span class="SNum">1</span>
    <span class="SCmp">#assert</span>(<span class="SItr">#stringof</span>(<span class="SCst">X</span>) == <span class="SStr">"1"</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#stringof</span>(<span class="SCst">X</span> + <span class="SNum">10</span>) == <span class="SStr">"11"</span>)
}

</span></div>
<p>The <span class="code-inline">#nameof</span> intrinsic returns the name of a variable, function, etc., as a string.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">const</span> <span class="SCst">X</span> = <span class="SNum">1</span>
    <span class="SCmp">#assert</span>(<span class="SItr">#nameof</span>(<span class="SCst">X</span>) == <span class="SStr">"X"</span>)
}

</span></div>
<h3 id="_003_004_constants_swg">Constants</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Constants_with__const_">Constants with <span class="code-inline">const</span></h3>
<p>Using <span class="code-inline">const</span> means the value must be <b>known by the compiler</b> at compile time. The compiler embeds the constant’s value directly into the compiled code, removing any runtime memory usage for simple types like integers or strings.</p>
<p>In other words, the compiler replaces every occurrence of a constant with its literal value, leading to optimized and efficient code execution.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SCmt">// Immutable compile-time constants</span>
    <span class="SKwd">const</span> a = <span class="SNum">666</span>
    <span class="SCmp">#assert</span>(a == <span class="SNum">666</span>)

    <span class="SKwd">const</span> b: <span class="STpe">string</span> = <span class="SStr">"string"</span>
    <span class="SCmp">#assert</span>(b == <span class="SStr">"string"</span>)
}

</span></div>
<h3 id="Constants_with_Complex_Types">Constants with Complex Types</h3>
<p>Swag also supports constants with complex data types, such as arrays and structures. When declared, the data is stored in the program's data segment, which occupies memory. The memory address of such constants can be accessed at runtime, allowing indirect manipulation through pointers.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h4 id="Static_Arrays">Static Arrays</h4>
<p>A static array has a fixed size. In this example, the constant array <span class="code-inline">a</span> contains three elements of type <span class="code-inline">s32</span> (signed 32-bit integers).</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">const</span> a: [<span class="SNum">3</span>] <span class="STpe">s32</span> = [<span class="SNum">0</span>, <span class="SNum">1</span>, <span class="SNum">2</span>]
    <span class="SKwd">let</span> ptr = <span class="SKwd">cast</span>(<span class="SKwd">const</span> [*] <span class="STpe">s32</span>) &amp;a[<span class="SNum">0</span>]
    <span class="SItr">@assert</span>(ptr[<span class="SNum">0</span>] == <span class="SNum">0</span>)
    <span class="SItr">@assert</span>(ptr[<span class="SNum">2</span>] == <span class="SNum">2</span>)

    <span class="SCmt">// Compile-time verification of array contents</span>
    <span class="SCmp">#assert</span>(a[<span class="SNum">0</span>] == <span class="SNum">0</span>)
    <span class="SCmp">#assert</span>(a[<span class="SNum">1</span>] == <span class="SNum">1</span>)
    <span class="SCmp">#assert</span>(a[<span class="SNum">2</span>] == <span class="SNum">2</span>)
}

</span></div>
<h4 id="Multidimensional_Arrays">Multidimensional Arrays</h4>
<p>This example demonstrates a constant 4×4 matrix of 32-bit floating-point values (<span class="code-inline">f32</span>). Arrays will be explored in more detail later in this documentation.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">const</span> <span class="SCst">M4x4</span>: [<span class="SNum">4</span>, <span class="SNum">4</span>] <span class="STpe">f32</span> = [
        [<span class="SNum">1</span>, <span class="SNum">0</span>, <span class="SNum">0</span>, <span class="SNum">0</span>],
        [<span class="SNum">0</span>, <span class="SNum">1</span>, <span class="SNum">0</span>, <span class="SNum">0</span>],
        [<span class="SNum">0</span>, <span class="SNum">0</span>, <span class="SNum">1</span>, <span class="SNum">0</span>],
        [<span class="SNum">0</span>, <span class="SNum">0</span>, <span class="SNum">0</span>, <span class="SNum">1</span>]]
}

</span></div>
<h3 id="Key_Difference_Between__let__and__const_">Key Difference Between <span class="code-inline">let</span> and <span class="code-inline">const</span></h3>
<p>The key distinction between <span class="code-inline">let</span> and <span class="code-inline">const</span> lies in <b>when</b> their values are determined:</p>
<ul>
<li>A <span class="code-inline">const</span> value is fixed and known <b>at compile time</b>.</li>
<li>A <span class="code-inline">let</span> value can be assigned <b>at runtime</b>, allowing computation before assignment.</li>
</ul>
<p>Despite this difference, both <span class="code-inline">let</span> and <span class="code-inline">const</span> enforce immutability — once a value is assigned, it cannot be changed.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_003_005_variables_swg">Variables</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Variable_Declaration">Variable Declaration</h3>
<p>Variables are declared using the <span class="code-inline">let</span> or <span class="code-inline">var</span> keyword, followed by a <span class="code-inline">:</span> and the variable’s type.</p>
<ul>
<li><b>'let'</b> — Declares an immutable variable. Once assigned, its value cannot change.</li>
<li><b>'var'</b> — Declares a mutable variable. Its value can be modified after initialization.</li>
</ul>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> a: <span class="STpe">u32</span> = <span class="SNum">1</span>     <span class="SCmt">// Immutable variable</span>
    <span class="SItr">@assert</span>(a == <span class="SNum">1</span>)

    <span class="SKwd">let</span> b: <span class="STpe">string</span> = <span class="SStr">"string"</span>
    <span class="SItr">@assert</span>(b == <span class="SStr">"string"</span>)

    <span class="SKwd">var</span> c: <span class="STpe">s32</span> = <span class="SNum">42</span>     <span class="SCmt">// Mutable variable</span>
    c += <span class="SNum">1</span>
    <span class="SItr">@assert</span>(c == <span class="SNum">43</span>)
}

</span></div>
<h3 id="Multiple_Variable_Declarations">Multiple Variable Declarations</h3>
<p>Swag allows declaring multiple variables of the same type on a single line.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> a, b: <span class="STpe">u32</span> = <span class="SNum">123</span>
    <span class="SItr">@assert</span>(a == <span class="SNum">123</span>)
    <span class="SItr">@assert</span>(b == <span class="SNum">123</span>)
}

</span></div>
<p>Multiple variables of different types can also be declared on one line.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> a: <span class="STpe">u32</span> = <span class="SNum">12</span>, b: <span class="STpe">f32</span> = <span class="SNum">1.5</span>
    <span class="SItr">@assert</span>(a == <span class="SNum">12</span>)
    <span class="SItr">@assert</span>(b == <span class="SNum">1.5</span>)
}

</span></div>
<h3 id="Default_Initialization">Default Initialization</h3>
<p>If a variable is declared without an explicit value, it is initialized with its type's default value. The explicit <span class="code-inline">undefined</span> escape below is the only way this section deliberately bypasses that default initialization.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> a: <span class="STpe">bool</span>
    <span class="SItr">@assert</span>(a == <span class="SKwd">false</span>)

    <span class="SKwd">var</span> b: <span class="SItr">#null</span> <span class="STpe">string</span>
    <span class="SItr">@assert</span>(b == <span class="SKwd">null</span>)

    <span class="SKwd">var</span> c: <span class="STpe">f64</span>
    <span class="SItr">@assert</span>(c == <span class="SNum">0</span>)
}

</span></div>
<h3 id="Uninitialized_Variables">Uninitialized Variables</h3>
<p>To skip default initialization, you can assign <span class="code-inline">undefined</span>. This prevents automatic initialization but leaves the variable in an undefined state, which should be used cautiously.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> a: <span class="STpe">bool</span>         = <span class="SKwd">undefined</span>
    <span class="SKwd">var</span> b: <span class="SItr">#null</span> <span class="STpe">string</span> = <span class="SKwd">undefined</span>
}

</span></div>
<h3 id="Type_Inference">Type Inference</h3>
<p>Swag supports <b>type inference</b>, automatically determining a variable’s type based on its assigned value. This often eliminates the need for explicit type annotations.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> a = <span class="SNum">1.5</span>
    <span class="SItr">@assert</span>(a == <span class="SNum">1.5</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(a) == <span class="STpe">f32</span>)

    <span class="SKwd">let</span> b = <span class="SStr">"string"</span>
    <span class="SItr">@assert</span>(b == <span class="SStr">"string"</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(b) == <span class="STpe">string</span>)

    <span class="SKwd">let</span> c = <span class="SNum">1.5</span>'<span class="STpe">f64</span>
    <span class="SItr">@assert</span>(c == <span class="SNum">1.5</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(c) == <span class="STpe">f64</span>)
}

</span></div>
<p>Type inference also applies when declaring multiple variables simultaneously.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> a, b = <span class="SKwd">true</span>
    <span class="SItr">@assert</span>(a == <span class="SKwd">true</span>)
    <span class="SItr">@assert</span>(b == <span class="SKwd">true</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(a) == <span class="SItr">#typeof</span>(<span class="SKwd">true</span>))
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(b) == <span class="SItr">#typeof</span>(a))

    <span class="SKwd">let</span> c = <span class="SNum">1.5</span>, d = <span class="SStr">"string"</span>
    <span class="SItr">@assert</span>(c == <span class="SNum">1.5</span>)
    <span class="SItr">@assert</span>(d == <span class="SStr">"string"</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(c) == <span class="STpe">f32</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(d) == <span class="STpe">string</span>)
}

</span></div>
<h3 id="Special_Variables">Special Variables</h3>
<p>Swag provides attributes that modify how variables are stored or accessed.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h4 id="Thread-Local_Storage">Thread-Local Storage</h4>
<p>Global variables marked with <span class="code-inline">#[Swag.Tls]</span> are stored in thread-local storage. Each thread has its own copy of the variable.</p>
<div class="code-block"><span class="SCde"><span class="SAtr">#[Swag.Tls]</span>
<span class="SKwd">var</span> <span class="SCst">G</span> = <span class="SNum">0</span>     <span class="SCmt">// Thread-local global variable</span>

</span></div>
<h4 id="Global_Variables">Global Variables</h4>
<p>A local variable can be marked with <span class="code-inline">#[Swag.Global]</span> to make it global within its function’s scope. It behaves similarly to <span class="code-inline">static</span> variables in C/C++, retaining its value between function calls.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">func</span> <span class="SFct">toto</span>()-&gt;<span class="STpe">s32</span>
    {
        <span class="SAtr">#[Swag.Global]</span>
        <span class="SKwd">var</span> <span class="SCst">G1</span> = <span class="SNum">0</span>
        <span class="SCst">G1</span> += <span class="SNum">1</span>
        <span class="SLgc">return</span> <span class="SCst">G1</span>
    }

    <span class="SItr">@assert</span>(<span class="SFct">toto</span>() == <span class="SNum">1</span>)
    <span class="SItr">@assert</span>(<span class="SFct">toto</span>() == <span class="SNum">2</span>)
    <span class="SItr">@assert</span>(<span class="SFct">toto</span>() == <span class="SNum">3</span>)
}

</span></div>
<h4 id="Compile-Time_Variables">Compile-Time Variables</h4>
<p>Global variables marked with <span class="code-inline">#[Swag.Compiler]</span> exist only during compile time and are excluded from the final runtime code.</p>
<div class="code-block"><span class="SCde"><span class="SAtr">#[Swag.Compiler]</span>
<span class="SKwd">var</span> <span class="SCst">G2</span> = <span class="SNum">0</span>

<span class="SFct">#run</span>
{
    <span class="SCst">G2</span> += <span class="SNum">5</span>     <span class="SCmt">// Executes at compile time</span>
}

</span></div>
<h3 id="_003_006_operators_swg">Operators</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Arithmetic_Operators">Arithmetic Operators</h3>
<p>Arithmetic operators perform basic mathematical operations such as addition, subtraction, multiplication, division, and modulus (remainder).</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> x: <span class="STpe">s32</span> = <span class="SNum">10</span>

    <span class="SCmt">// Addition</span>
    x = x + <span class="SNum">1</span>

    <span class="SCmt">// Subtraction</span>
    x = x - <span class="SNum">1</span>

    <span class="SCmt">// Multiplication</span>
    x = x * <span class="SNum">2</span>

    <span class="SCmt">// Division</span>
    x = x / <span class="SNum">2</span>

    <span class="SCmt">// Modulus</span>
    x = x % <span class="SNum">2</span>
}

</span></div>
<h3 id="Bitwise_Operators">Bitwise Operators</h3>
<p>Bitwise operators manipulate individual bits of integral types. They include bitwise AND, OR, XOR, and bit shifting.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> x: <span class="STpe">s32</span> = <span class="SNum">10</span>

    x = x ^ <span class="SNum">2</span>                    <span class="SCmt">// XOR</span>
    x = x &amp; <span class="SNum">0b0000_0001</span>'<span class="STpe">s32</span>      <span class="SCmt">// AND</span>
    x = x | <span class="SKwd">cast</span>(<span class="STpe">s32</span>) <span class="SNum">0b0001</span>     <span class="SCmt">// OR</span>
    x = x &lt;&lt; <span class="SNum">1</span>                   <span class="SCmt">// Shift left</span>
    x = x &gt;&gt; <span class="SNum">1</span>                   <span class="SCmt">// Shift right</span>
}

</span></div>
<h3 id="Assignment_Operators">Assignment Operators</h3>
<p>Assignment operators perform an operation and immediately assign the result to the left operand, creating concise expressions.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> x: <span class="STpe">s32</span> = <span class="SNum">10</span>

    x += <span class="SNum">1</span>
    x -= <span class="SNum">1</span>
    x *= <span class="SNum">2</span>
    x /= <span class="SNum">2</span>
    x %= <span class="SNum">2</span>
    x ^= <span class="SNum">2</span>
    x |= <span class="SNum">0b0001</span>
    x &amp;= <span class="SNum">0b0001</span>
    x &lt;&lt;= <span class="SNum">1</span>
    x &gt;&gt;= <span class="SNum">1</span>
}

</span></div>
<h3 id="Unary_Operators">Unary Operators</h3>
<p>Unary operators operate on a single operand. These include logical NOT, bitwise NOT, and negation.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> x = <span class="SKwd">true</span>
    <span class="SKwd">var</span> y = <span class="SNum">0b0000_0001</span>'<span class="STpe">u8</span>
    <span class="SKwd">var</span> z = <span class="SNum">1</span>

    x = !x     <span class="SCmt">// Logical NOT</span>
    y = ~y     <span class="SCmt">// Bitwise NOT</span>
    z = -z     <span class="SCmt">// Negation</span>

    <span class="SItr">@assert</span>(z == -<span class="SNum">1</span>)
    <span class="SItr">@assert</span>(x == <span class="SKwd">false</span>)
    <span class="SItr">@assert</span>(y == <span class="SNum">0b1111_1110</span>)
}

</span></div>
<h3 id="Comparison_Operators">Comparison Operators</h3>
<p>Comparison operators compare two values and return a boolean result. They include equality, inequality, and relational comparisons.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    {
        <span class="SKwd">var</span> a = <span class="SKwd">false</span>
        a = <span class="SNum">1</span> == <span class="SNum">1</span> ? <span class="SKwd">true</span> : <span class="SKwd">false</span>
        a = <span class="SNum">1</span> != <span class="SNum">1</span> ? <span class="SKwd">true</span> : <span class="SKwd">false</span>
        a = <span class="SNum">1</span> &lt;= <span class="SNum">1</span> ? <span class="SKwd">true</span> : <span class="SKwd">false</span>
        a = <span class="SNum">1</span> &gt;= <span class="SNum">1</span> ? <span class="SKwd">true</span> : <span class="SKwd">false</span>
        a = <span class="SNum">1</span> &lt; <span class="SNum">1</span> ? <span class="SKwd">true</span> : <span class="SKwd">false</span>
        a = <span class="SNum">1</span> &gt; <span class="SNum">1</span> ? <span class="SKwd">true</span> : <span class="SKwd">false</span>
    }

    {
        <span class="SKwd">let</span> x = <span class="SNum">5</span>
        <span class="SKwd">let</span> y = <span class="SNum">10</span>
        <span class="SItr">@assert</span>(x == <span class="SNum">5</span>)
        <span class="SItr">@assert</span>(x != <span class="SNum">10</span>)
        <span class="SItr">@assert</span>(x &lt;= <span class="SNum">5</span>)
        <span class="SItr">@assert</span>(x &lt; <span class="SNum">10</span>)
        <span class="SItr">@assert</span>(x &gt;= <span class="SNum">5</span>)
        <span class="SItr">@assert</span>(x &gt; <span class="SNum">0</span>)
    }
}

</span></div>
<h3 id="Logical_Operators">Logical Operators</h3>
<p>Logical operators evaluate expressions and return a boolean result. Swag uses <span class="code-inline">and</span> and <span class="code-inline">or</span> instead of <span class="code-inline">&amp;&amp;</span> and <span class="code-inline">||</span> from C/C++.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> a = <span class="SKwd">false</span>
    a = (<span class="SNum">1</span> &gt; <span class="SNum">10</span>) <span class="SLgc">and</span> (<span class="SNum">10</span> &lt; <span class="SNum">1</span>)
    a = (<span class="SNum">1</span> &gt; <span class="SNum">10</span>) <span class="SLgc">or</span> (<span class="SNum">10</span> &lt; <span class="SNum">1</span>)
}

</span></div>
<h3 id="Ternary_Operator">Ternary Operator</h3>
<p>The ternary operator tests an expression and returns one of two values depending on whether the condition is true or false.</p>
<p>Syntax: <span class="code-inline">A = Condition ? B : C</span></p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> x = <span class="SKwd">true</span> ? <span class="SNum">1</span> : <span class="SNum">666</span>
    <span class="SItr">@assert</span>(x == <span class="SNum">1</span>)

    <span class="SKwd">let</span> y = (x == <span class="SNum">52</span>) ? <span class="SNum">1</span> : <span class="SNum">666</span>
    <span class="SItr">@assert</span>(y == <span class="SNum">666</span>)
}

</span></div>
<h3 id="Spaceship_Operator">Spaceship Operator</h3>
<p>The <span class="code-inline">&lt;=&gt;</span> operator returns -1, 0, or 1 depending on whether the left operand is less than, equal to, or greater than the right operand. The result type is <span class="code-inline">s32</span>.</p>
<div class="code-block"><span class="SCde"><span class="SCst">A</span> &lt;=&gt; <span class="SCst">B</span> == -<span class="SNum">1</span> <span class="SLgc">if</span> <span class="SCst">A</span> &lt; <span class="SCst">B</span>
<span class="SCst">A</span> &lt;=&gt; <span class="SCst">B</span> ==  <span class="SNum">0</span> <span class="SLgc">if</span> <span class="SCst">A</span> == <span class="SCst">B</span>
<span class="SCst">A</span> &lt;=&gt; <span class="SCst">B</span> ==  <span class="SNum">1</span> <span class="SLgc">if</span> <span class="SCst">A</span> &gt; <span class="SCst">B</span>
</span></div>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    {
        <span class="SKwd">let</span> a = -<span class="SNum">1.5</span> &lt;=&gt; <span class="SNum">2.31</span>
        <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(a) == <span class="STpe">s32</span>)
        <span class="SItr">@assert</span>(a == -<span class="SNum">1</span>)

        <span class="SItr">@assert</span>(-<span class="SNum">10</span> &lt;=&gt; <span class="SNum">10</span> == -<span class="SNum">1</span>)
        <span class="SItr">@assert</span>(<span class="SNum">10</span> &lt;=&gt; -<span class="SNum">10</span> == <span class="SNum">1</span>)
        <span class="SItr">@assert</span>(<span class="SNum">10</span> &lt;=&gt; <span class="SNum">10</span> == <span class="SNum">0</span>)
    }

    {
        <span class="SKwd">let</span> x1 = <span class="SNum">10</span> &lt;=&gt; <span class="SNum">20</span>
        <span class="SItr">@assert</span>(x1 == -<span class="SNum">1</span>)

        <span class="SKwd">let</span> x2 = <span class="SNum">20</span> &lt;=&gt; <span class="SNum">10</span>
        <span class="SItr">@assert</span>(x2 == <span class="SNum">1</span>)

        <span class="SKwd">let</span> x3 = <span class="SNum">20</span> &lt;=&gt; <span class="SNum">20</span>
        <span class="SItr">@assert</span>(x3 == <span class="SNum">0</span>)
    }
}

</span></div>
<h3 id="Null-Coalescing_Operator">Null-Coalescing Operator</h3>
<p>The <span class="code-inline">orelse</span> operator returns the left-hand expression when it is present, and the right-hand one when it is null. It substitutes a <b>missing</b> value, never a zero one, so the result is non-null even when the operand was not.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> a: <span class="SItr">#null</span> <span class="STpe">string</span> = <span class="SStr">"string1"</span>
    <span class="SKwd">let</span> b               = <span class="SStr">"string2"</span>

    <span class="SKwd">var</span> c = a <span class="SLgc">orelse</span> b
    <span class="SItr">@assert</span>(c == <span class="SStr">"string1"</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(c) == <span class="STpe">string</span>)     <span class="SCmt">// the result drops '#null'</span>

    a = <span class="SKwd">null</span>
    c = a <span class="SLgc">orelse</span> b
    <span class="SItr">@assert</span>(c == <span class="SStr">"string2"</span>)
}

</span></div>
<p>The left operand must therefore be of a type that can carry null: a pointer, <span class="code-inline">string</span>, <span class="code-inline">cstring</span>, a slice, an interface, or a function. A type that can never be null is rejected, because <span class="code-inline">orelse</span> would have nothing to substitute:</p>
<div class="code-block"><span class="SCde"><span class="SKwd">let</span> count = <span class="SNum">0</span>
<span class="SKwd">let</span> n = count <span class="SLgc">orelse</span> <span class="SNum">10</span>     <span class="SCmt">// error: 's32' can never be null</span>
</span></div>
<p>To substitute a <b>zero</b>, ask that question explicitly. It is a different test, and the ternary already expresses it:</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> count = <span class="SNum">0</span>
    <span class="SKwd">let</span> n     = count != <span class="SNum">0</span> ? count : <span class="SNum">10</span>
    <span class="SItr">@assert</span>(n == <span class="SNum">10</span>)
}

</span></div>
<div class="blockquote blockquote-note">
<div class="blockquote-title-block"><span class="blockquote-title">Note</span></div>
<p>For a pointer-like operand the test is on the POINTER, not on emptiness. An empty <span class="code-inline">string</span> is present, so it is returned as-is; only a null one falls back.</p>
</div>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> empty = <span class="SStr">""</span>
    <span class="SItr">@assert</span>((empty <span class="SLgc">orelse</span> <span class="SStr">"fallback"</span>) == <span class="SStr">""</span>)

    <span class="SKwd">var</span> missing: <span class="SItr">#null</span> <span class="STpe">string</span> = <span class="SKwd">null</span>
    <span class="SItr">@assert</span>((missing <span class="SLgc">orelse</span> <span class="SStr">"fallback"</span>) == <span class="SStr">"fallback"</span>)
}

</span></div>
<h3 id="Type_Promotion">Type Promotion</h3>
<p>Unlike C, Swag does not automatically promote small integer types (8-bit or 16-bit) to 32 bits. When operands differ in type, promotion follows the wider type. If a signed and an unsigned integer have the same width, the unsigned type wins.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(<span class="SNum">0</span>'<span class="STpe">u8</span> + <span class="SNum">1</span>'<span class="STpe">u8</span>) == <span class="STpe">u8</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(<span class="SNum">0</span>'<span class="STpe">u8</span> + <span class="SNum">1</span>'<span class="STpe">u16</span>) == <span class="STpe">u16</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(<span class="SNum">0</span>'<span class="STpe">u8</span> + <span class="SNum">1</span>'<span class="STpe">u32</span>) == <span class="STpe">u32</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(<span class="SNum">0</span>'<span class="STpe">u8</span> + <span class="SNum">1</span>'<span class="STpe">u64</span>) == <span class="STpe">u64</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(<span class="SNum">0</span>'<span class="STpe">u8</span> + <span class="SNum">1</span>'<span class="STpe">s8</span>) == <span class="STpe">u8</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(<span class="SNum">0</span>'<span class="STpe">u8</span> + <span class="SNum">1</span>'<span class="STpe">s16</span>) == <span class="STpe">s16</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(<span class="SNum">0</span>'<span class="STpe">u8</span> + <span class="SNum">1</span>'<span class="STpe">s32</span>) == <span class="STpe">s32</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(<span class="SNum">0</span>'<span class="STpe">u8</span> + <span class="SNum">1</span>'<span class="STpe">s64</span>) == <span class="STpe">s64</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(<span class="SNum">0</span>'<span class="STpe">u8</span> + <span class="SNum">1</span>'<span class="STpe">f32</span>) == <span class="STpe">f32</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(<span class="SNum">0</span>'<span class="STpe">u8</span> + <span class="SNum">1</span>'<span class="STpe">f64</span>) == <span class="STpe">f64</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(<span class="SNum">0</span>'<span class="STpe">s8</span> + <span class="SNum">1</span>'<span class="STpe">u16</span>) == <span class="STpe">u16</span>)
}

</span></div>
<p>To prevent overflow during small integer operations, you can apply the <span class="code-inline">#prom</span> modifier to promote operands to at least 32 bits before the operation.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(<span class="SNum">255</span>'<span class="STpe">u8</span> + <span class="SItr">#prom</span> <span class="SNum">1</span>'<span class="STpe">u8</span>) == <span class="STpe">u32</span>)
    <span class="SCmp">#assert</span>(<span class="SNum">255</span>'<span class="STpe">u8</span> + <span class="SItr">#prom</span> <span class="SNum">1</span>'<span class="STpe">u8</span> == <span class="SNum">256</span>)
}

</span></div>
<h3 id="Operator_Precedence">Operator Precedence</h3>
<p>Precedence runs from tightest (top) to loosest (bottom). Operators listed on the same line share a level.</p>
<div class="code-block"><span class="SCde">! ~ - +      (prefix)
* / %
+ - ++
&gt;&gt; &lt;&lt;
&amp;
^
|
&lt;=&gt; &lt; &lt;= &gt; &gt;=
== !=
<span class="SLgc">and</span>
<span class="SLgc">or</span>
<span class="SLgc">orelse</span>  ? :
</span></div>
<p>The prefix operators bind tighter than every binary operator, so '!a == b' parses as '(!a) == b' and '-a <i> b' parses as '(-a) </i> b'. The string concatenation operator <span class="code-inline">++</span> shares the additive level.</p>
<p>When two operators share the same precedence level, expressions are evaluated from left to right. The loosest level, <span class="code-inline">orelse</span> and the ternary, groups to the right: 'a orelse b ? c : d' parses as 'a orelse (b ? c : d)'.</p>
<p>Unlike C, the bitwise operators '&amp; ^ |' all bind <b>tighter</b> than the comparison operators. This makes 'flags &amp; Mask == 0' parse as '(flags &amp; Mask) == 0', which is almost always the intent, so the classic C footgun is avoided by design. Among the comparisons, the ordering operators '&lt;=&gt; &lt; &lt;= &gt; &gt;=' bind tighter than the equality operators '== !=', so 'a &lt; b == c' parses as '(a &lt; b) == c'.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SItr">@assert</span>(<span class="SNum">10</span> + <span class="SNum">2</span> * <span class="SNum">3</span> == <span class="SNum">16</span>)
    <span class="SItr">@assert</span>((<span class="SNum">10</span> + <span class="SNum">2</span>) * <span class="SNum">3</span> == <span class="SNum">36</span>)
    <span class="SItr">@assert</span>((<span class="SNum">5</span> + <span class="SNum">3</span> &lt; <span class="SNum">10</span> - <span class="SNum">2</span>) == <span class="SKwd">false</span>)
    <span class="SItr">@assert</span>((<span class="SKwd">false</span> <span class="SLgc">and</span> <span class="SKwd">false</span> <span class="SLgc">or</span> <span class="SKwd">true</span>) == <span class="SKwd">true</span>)
    <span class="SItr">@assert</span>((<span class="SNum">10</span> &amp; <span class="SNum">2</span> &lt;&lt; <span class="SNum">1</span>) == <span class="SNum">0</span>)
    <span class="SItr">@assert</span>(((<span class="SNum">10</span> &amp; <span class="SNum">2</span>) &lt;&lt; <span class="SNum">1</span>) == <span class="SNum">4</span>)

    <span class="SCmt">// '^' binds tighter than '|': parses as 1 | (2 ^ 3) == 1 | 1 == 1.</span>
    <span class="SItr">@assert</span>((<span class="SNum">1</span> | <span class="SNum">2</span> ^ <span class="SNum">3</span>) == <span class="SNum">1</span>)

    <span class="SCmt">// Bitwise binds tighter than comparison: parses as (2 &amp; 3) == 2.</span>
    <span class="SCmt">// Under the C ordering this would be 2 &amp; (3 == 2) and would not even compile.</span>
    <span class="SItr">@assert</span>(<span class="SNum">2</span> &amp; <span class="SNum">3</span> == <span class="SNum">2</span>)

    <span class="SCmt">// Ordering comparisons bind tighter than equality: parses as (1 &lt; 2) == true.</span>
    <span class="SItr">@assert</span>(<span class="SNum">1</span> &lt; <span class="SNum">2</span> == <span class="SKwd">true</span>)

    <span class="SCmt">// The spaceship shares the ordering level, still tighter than equality: (1 &lt;=&gt; 2) == -1.</span>
    <span class="SItr">@assert</span>(<span class="SNum">1</span> &lt;=&gt; <span class="SNum">2</span> == -<span class="SNum">1</span>)

    <span class="SCmt">// Prefix operators bind tighter than any binary operator.</span>
    <span class="SItr">@assert</span>((!<span class="SKwd">false</span> == <span class="SKwd">true</span>) == <span class="SKwd">true</span>)
    <span class="SItr">@assert</span>(-<span class="SNum">2</span> * <span class="SNum">3</span> == -<span class="SNum">6</span>)
    <span class="SItr">@assert</span>(~<span class="SNum">0</span>'<span class="STpe">u8</span> == <span class="SNum">255</span>)

    <span class="SCmt">// 'orelse' and the ternary sit at the loosest level and group to the right.</span>
    <span class="SKwd">let</span> a: <span class="SItr">#null</span> <span class="STpe">string</span> = <span class="SKwd">null</span>
    <span class="SItr">@assert</span>((a <span class="SLgc">orelse</span> (<span class="SKwd">false</span> ? <span class="SStr">"x"</span> : <span class="SStr">"y"</span>)) == <span class="SStr">"y"</span>)
}

</span></div>
<h3 id="_003_007_cast_swg">Cast</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Explicit_Cast_with__cast_">Explicit Cast with <span class="code-inline">cast</span></h3>
<p>Explicit casting converts a value from one type to another using the syntax 'cast(type) value'. This transformation changes the type of <span class="code-inline">value</span> to the specified <span class="code-inline">type</span>.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> x = <span class="SNum">1.0</span>     <span class="SCmt">// Defaults to 'f32'</span>
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(x) == <span class="STpe">f32</span>)

    <span class="SKwd">let</span> y = <span class="SKwd">cast</span>(<span class="STpe">s32</span>) x     <span class="SCmt">// Explicit cast to 's32'</span>
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(y) == <span class="STpe">s32</span>)
    <span class="SItr">@assert</span>(y == <span class="SNum">1</span>)
}

</span></div>
<h3 id="Automatic_Cast_with__cast___">Automatic Cast with <span class="code-inline">cast()</span></h3>
<p>A <span class="code-inline">cast()</span> without a type performs an <b>automatic cast</b>, allowing the compiler to infer the target type based on the left-hand side of the assignment.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> x: <span class="STpe">f32</span> = <span class="SNum">1.0</span>
    <span class="SKwd">let</span> y: <span class="STpe">s32</span> = <span class="SKwd">cast</span>() x
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(y) == <span class="STpe">s32</span>)
    <span class="SItr">@assert</span>(y == <span class="SNum">1</span>)
}

</span></div>
<p>Automatic casts can also be applied when passing function arguments.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">testAutoCast</span>(x: <span class="STpe">s32</span>)
{
    <span class="SItr">@assert</span>(x == <span class="SNum">1</span>)
}

<span class="SFct">#test</span>
{
    <span class="SFct">testAutoCast</span>(<span class="SKwd">cast</span>() <span class="SNum">1.4</span>)     <span class="SCmt">// Automatically cast to 's32'</span>
}

</span></div>
<h3 id="Bit_Cast">Bit Cast</h3>
<p>The <span class="code-inline">#bit</span> cast mode performs a <b>bit-level reinterpretation</b> of a value’s type without altering its underlying bit pattern. Source and destination types must have the same size.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> x: <span class="STpe">f32</span> = <span class="SNum">1.0</span>
    <span class="SKwd">let</span> y: <span class="STpe">u32</span> = <span class="SKwd">cast</span> <span class="SItr">#bit</span> (<span class="STpe">u32</span>) x
    <span class="SItr">@assert</span>(y == <span class="SNum">0x3F800000</span>)     <span class="SCmt">// 1.0 in IEEE 754 format</span>

    <span class="SCmp">#assert</span>(<span class="SKwd">cast</span> <span class="SItr">#bit</span> (<span class="STpe">u32</span>) <span class="SNum">1.0</span> == <span class="SNum">0x3F800000</span>)
    <span class="SCmp">#assert</span>(<span class="SKwd">cast</span> <span class="SItr">#bit</span> (<span class="STpe">f32</span>) <span class="SNum">0x3F800000</span> == <span class="SNum">1.0</span>)
}

</span></div>
<p>Bitcasting also allows reinterpreting an integer’s bit pattern as a floating-point value, or vice versa.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> rawBits: <span class="STpe">u32</span> = <span class="SNum">0x40490FDB</span>
    <span class="SKwd">let</span> pi:      <span class="STpe">f32</span> = <span class="SKwd">cast</span> <span class="SItr">#bit</span> (<span class="STpe">f32</span>) rawBits
    <span class="SItr">@assert</span>(pi == <span class="SNum">3.1415927</span>)

    <span class="SKwd">let</span> backToBits: <span class="STpe">u32</span> = <span class="SKwd">cast</span> <span class="SItr">#bit</span> (<span class="STpe">u32</span>) pi
    <span class="SItr">@assert</span>(backToBits == <span class="SNum">0x40490FDB</span>)
}

</span></div>
<h3 id="Implicit_Casts">Implicit Casts</h3>
<p>Swag supports <b>implicit casts</b>, automatically converting between compatible types when no data loss or precision loss can occur. These conversions happen without requiring an explicit <span class="code-inline">cast</span> statement.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h4 id="Implicit_Cast_Rules">Implicit Cast Rules</h4>
<ol>
<li><b>Widening conversions</b> — Allowed when converting from smaller to larger</li>
</ol>
<p>types, such as <span class="code-inline">s8</span> → <span class="code-inline">s16</span> or <span class="code-inline">f32</span> → <span class="code-inline">f64</span>.</p>
<ol>
<li><b>Sign preservation</b> — Implicit signed/unsigned conversions occur only if</li>
</ol>
<p>the value fits in the destination type.</p>
<ol>
<li><b>No narrowing conversions</b> — Conversions that could lose precision or range</li>
</ol>
<p>require an explicit cast.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> x: <span class="STpe">s16</span> = <span class="SNum">1</span>'<span class="STpe">s8</span>
    <span class="SKwd">let</span> y: <span class="STpe">s32</span> = <span class="SNum">1</span>'<span class="STpe">s16</span>
    <span class="SKwd">let</span> z: <span class="STpe">s64</span> = <span class="SNum">1</span>'<span class="STpe">s32</span>

    <span class="SKwd">let</span> a: <span class="STpe">u16</span> = <span class="SNum">255</span>'<span class="STpe">u8</span>
    <span class="SKwd">let</span> b: <span class="STpe">u32</span> = <span class="SNum">65535</span>'<span class="STpe">u16</span>
    <span class="SKwd">let</span> c: <span class="STpe">u64</span> = <span class="SNum">4294967295</span>'<span class="STpe">u32</span>

    <span class="SKwd">let</span> d: <span class="STpe">f64</span> = <span class="SNum">1.23</span>'<span class="STpe">f32</span>
}

</span></div>
<h3 id="Disallowed_Implicit_Casts">Disallowed Implicit Casts</h3>
<p>Swag forbids implicit casts that may lose data or precision. In such cases, an explicit cast is required. The <span class="code-inline">#wrap</span> cast mode can be used to acknowledge potential data loss.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SCmt">// Explicit cast from 's16' to 's8' required</span>
    <span class="SKwd">let</span> z0: <span class="STpe">s16</span> = <span class="SNum">256</span>
    <span class="SKwd">let</span> z1: <span class="STpe">s8</span>  = <span class="SKwd">cast</span> <span class="SItr">#wrap</span> (<span class="STpe">s8</span>) z0
    <span class="SItr">@assert</span>(z1 == <span class="SNum">0</span>)

    <span class="SCmt">// Explicit cast from 'u16' to 's16' required</span>
    <span class="SKwd">let</span> u_val: <span class="STpe">u16</span> = <span class="SNum">65535</span>
    <span class="SKwd">let</span> s_val: <span class="STpe">s16</span> = <span class="SKwd">cast</span> <span class="SItr">#wrap</span> (<span class="STpe">s16</span>) u_val
    <span class="SItr">@assert</span>(s_val == -<span class="SNum">1</span>)

    <span class="SCmt">// Explicit cast from 'f64' to 'f32' required</span>
    <span class="SKwd">let</span> large_float:   <span class="STpe">f64</span> = <span class="SNum">1.23456789012345611111</span>
    <span class="SKwd">let</span> smaller_float: <span class="STpe">f32</span> = <span class="SKwd">cast</span>(<span class="STpe">f32</span>) large_float
}

</span></div>
<h3 id="_003_008_alias_swg">Alias</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Type_Alias">Type Alias</h3>
<p>An <span class="code-inline">alias</span> creates a shorthand or alternative name for an existing type. This can improve readability, reduce repetition, and simplify the use of complex types. A type alias does not create a new type — it simply provides a new name for an existing one.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="Basic_Type_Alias">Basic Type Alias</h3>
<p>Using <span class="code-inline">alias</span>, you can define a shorthand for any existing type. The alias can be used interchangeably with the original type throughout your code.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">enum</span> <span class="SCst">RGB</span> { <span class="SCst">R</span>, <span class="SCst">G</span>, <span class="SCst">B</span> }
    <span class="SItr">@assert</span>(<span class="SCst">RGB</span>.<span class="SCst">R</span> == <span class="SNum">0</span>)

    <span class="SKwd">alias</span> <span class="SCst">Color</span> = <span class="SCst">RGB</span>
    <span class="SItr">@assert</span>(<span class="SCst">Color</span>.<span class="SCst">G</span> == <span class="SNum">1</span>)
}

</span></div>
<h3 id="Aliasing_Primitive_Types">Aliasing Primitive Types</h3>
<p>Aliases can be created for primitive types to make your code more expressive or domain-specific, improving clarity when a type has a specific contextual meaning.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">alias</span> <span class="SCst">Float32</span> = <span class="STpe">f32</span>
    <span class="SKwd">alias</span> <span class="SCst">Float64</span> = <span class="STpe">f64</span>

    <span class="SKwd">var</span> x: <span class="SCst">Float32</span> = <span class="SNum">1.0</span>
    <span class="SKwd">var</span> y: <span class="SCst">Float64</span> = <span class="SNum">1.0</span>

    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(<span class="SCst">Float32</span>) == <span class="STpe">f32</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(<span class="SCst">Float64</span>) == <span class="STpe">f64</span>)
}

</span></div>
<h3 id="Strict_Type_Alias">Strict Type Alias</h3>
<p>When you need stronger type safety, you can use the <span class="code-inline">#[Swag.Strict]</span> attribute. This makes the alias a <b>distinct type</b>, disallowing implicit conversions between the alias and its base type. Explicit casting is still permitted.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SAtr">#[Swag.Strict]</span>
    <span class="SKwd">alias</span> <span class="SCst">MyType</span> = <span class="STpe">s32</span>
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(<span class="SCst">MyType</span>) != <span class="STpe">s32</span>)

    <span class="SKwd">let</span> x: <span class="SCst">MyType</span> = <span class="SKwd">cast</span>(<span class="SCst">MyType</span>) <span class="SNum">0</span>
    <span class="SKwd">let</span> y: <span class="STpe">s32</span>    = <span class="SKwd">cast</span>(<span class="STpe">s32</span>) x
}

</span></div>
<h3 id="Name_Alias">Name Alias</h3>
<p>The <span class="code-inline">alias</span> keyword can also create shortcuts for functions, variables, or namespaces. This helps simplify long names and improve code readability.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h4 id="Function_Name_Alias">Function Name Alias</h4>
<p>A function can be aliased to a shorter or more convenient name, which is especially useful for lengthy or descriptive function names.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">func</span> <span class="SFct">thisIsABigFunctionName</span>(x: <span class="STpe">s32</span>) =&gt; x * x
    <span class="SKwd">alias</span> myFunc = thisIsABigFunctionName
    <span class="SItr">@assert</span>(<span class="SFct">myFunc</span>(<span class="SNum">4</span>) == <span class="SNum">16</span>)
}

</span></div>
<h4 id="Variable_and_Namespace_Alias">Variable and Namespace Alias</h4>
<p>You can alias variables or namespaces to shorter names for easier access, especially in large codebases with long identifiers.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> myLongVariableName: <span class="STpe">s32</span> = <span class="SNum">0</span>
    <span class="SKwd">alias</span> short = myLongVariableName
    short += <span class="SNum">2</span>
    <span class="SItr">@assert</span>(myLongVariableName == <span class="SNum">2</span>)
}

</span></div>
<h2 id="_004_000_data_structures_swg">Data Structures</h2>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>
</span></div>
<p>Swag provides fixed arrays, slices, tuples, enums, unions, pointers, references, and the type-erased <span class="code-inline">any</span> value. Choose the representation that matches ownership and lifetime: arrays own inline storage, slices borrow a contiguous range, and pointers make indirection and nullability explicit.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_004_001_array_swg">Array</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Static_Arrays_in_Swag">Static Arrays in Swag</h3>
<p>Static arrays are fixed-size arrays where the size is known at compile time. Unlike dynamic arrays from the <span class="code-inline">Std.Core</span> module, they cannot grow or shrink during execution. Static arrays are ideal when size and memory usage are deterministic.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="Declaring_a_Static_Array">Declaring a Static Array</h3>
<p>A static array is declared using the syntax '[N] type', where <span class="code-inline">N</span> is the number of elements.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> array: [<span class="SNum">2</span>] <span class="STpe">s32</span>
    array[<span class="SNum">0</span>] = <span class="SNum">1</span>
    array[<span class="SNum">1</span>] = <span class="SNum">2</span>
}

</span></div>
<h3 id="Array_Size_and_Memory">Array Size and Memory</h3>
<p>The <span class="code-inline">@countof</span> intrinsic returns the number of elements in an array, while <span class="code-inline">#sizeof</span> returns the total memory size in bytes.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> array: [<span class="SNum">2</span>] <span class="STpe">s32</span>
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(array).count == <span class="SNum">2</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">@countof</span>(array) == <span class="SNum">2</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#sizeof</span>(array) == <span class="SNum">2</span> * <span class="SItr">#sizeof</span>(<span class="STpe">s32</span>))
}

</span></div>
<h3 id="Obtaining_the_Address_of_an_Array">Obtaining the Address of an Array</h3>
<p>The <span class="code-inline">@dataof</span> intrinsic retrieves the address of the first element in an array.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> array: [<span class="SNum">2</span>] <span class="STpe">s32</span>
    <span class="SKwd">var</span> ptr0 = <span class="SItr">@dataof</span>(array)
    ptr0[<span class="SNum">0</span>] = <span class="SNum">1</span>

    <span class="SKwd">var</span> ptr1 = <span class="SKwd">cast</span>([*] <span class="STpe">s32</span>) &amp;array[<span class="SNum">0</span>]
    ptr1[<span class="SNum">1</span>] = <span class="SNum">2</span>

    <span class="SItr">@assert</span>(array[<span class="SNum">0</span>] == <span class="SNum">1</span>)
    <span class="SItr">@assert</span>(array[<span class="SNum">1</span>] == <span class="SNum">2</span>)
}

</span></div>
<h3 id="Array_Literals">Array Literals</h3>
<p>An array literal is a list of elements enclosed in brackets '[A, B, ...]'.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> arr = [<span class="SNum">1</span>, <span class="SNum">2</span>, <span class="SNum">3</span>, <span class="SNum">4</span>]
    <span class="SCmp">#assert</span>(<span class="SItr">@countof</span>(arr) == <span class="SNum">4</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(arr) == <span class="SItr">#type</span> [<span class="SNum">4</span>] <span class="STpe">s32</span>)
}

</span></div>
<h3 id="Type_Deduction_in_Arrays">Type Deduction in Arrays</h3>
<p>Swag can deduce array size and element type from the initialization expression.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> array: [?] <span class="STpe">s32</span> = [<span class="SNum">1</span>, <span class="SNum">2</span>]
    <span class="SItr">@assert</span>(array[<span class="SNum">0</span>] == <span class="SNum">1</span>)
    <span class="SItr">@assert</span>(array[<span class="SNum">1</span>] == <span class="SNum">2</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">@countof</span>(array) == <span class="SNum">2</span>)
    <span class="SKwd">var</span> array1 = [<span class="SStr">"10"</span>, <span class="SStr">"20"</span>, <span class="SStr">"30"</span>]
    <span class="SItr">@assert</span>(array1[<span class="SNum">0</span>] == <span class="SStr">"10"</span>)
    <span class="SItr">@assert</span>(array1[<span class="SNum">1</span>] == <span class="SStr">"20"</span>)
    <span class="SItr">@assert</span>(array1[<span class="SNum">2</span>] == <span class="SStr">"30"</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">@countof</span>(array1) == <span class="SNum">3</span>)
}

</span></div>
<h3 id="Default_Initialization">Default Initialization</h3>
<p>Static arrays are automatically initialized with zero values (0 for numbers, <span class="code-inline">null</span> for strings, <span class="code-inline">false</span> for booleans, etc.) unless specified otherwise.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> array: [<span class="SNum">2</span>] <span class="STpe">s32</span>
    <span class="SItr">@assert</span>(array[<span class="SNum">0</span>] == <span class="SNum">0</span>)
    <span class="SItr">@assert</span>(array[<span class="SNum">1</span>] == <span class="SNum">0</span>)
}

</span></div>
<h3 id="Preventing_Default_Initialization">Preventing Default Initialization</h3>
<p>You can skip default initialization by using <span class="code-inline">undefined</span>, which improves performance when the array will be manually initialized later.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> array: [<span class="SNum">100</span>] <span class="STpe">s32</span> = <span class="SKwd">undefined</span>
}

</span></div>
<h3 id="Constant_Arrays">Constant Arrays</h3>
<p>Arrays initialized with compile-time values can be declared as <span class="code-inline">const</span>, making them immutable after declaration.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">const</span> array = [<span class="SNum">1</span>, <span class="SNum">2</span>, <span class="SNum">3</span>, <span class="SNum">4</span>]
    <span class="SCmp">#assert</span>(array[<span class="SNum">0</span>] == <span class="SNum">1</span>)
    <span class="SCmp">#assert</span>(array[<span class="SNum">3</span>] == <span class="SNum">4</span>)
}

</span></div>
<h3 id="Type_Inference_from_Array_Literals">Type Inference from Array Literals</h3>
<p>If no explicit type is specified, Swag infers one element type that fits every element, following the usual promotion rules. It is not simply the type of the first element: a later element widens the result, and an explicit suffix on the first one does not pin it down.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">let</span> widened = [<span class="SNum">1</span>'<span class="STpe">s32</span>, <span class="SNum">2.75</span>, <span class="SNum">3</span>]     <span class="SCmt">// a '[3] f32', not a '[3] s32'</span>
</span></div>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> arr = [<span class="SNum">1</span>'<span class="STpe">f64</span>, <span class="SNum">2</span>, <span class="SNum">3</span>, <span class="SNum">4</span>]
    <span class="SCmp">#assert</span>(<span class="SItr">@countof</span>(arr) == <span class="SNum">4</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(arr) == <span class="SItr">#type</span> [<span class="SNum">4</span>] <span class="STpe">f64</span>)
    <span class="SItr">@assert</span>(arr[<span class="SNum">3</span>] == <span class="SNum">4.0</span>)
}

</span></div>
<h3 id="Multi-Dimensional_Arrays">Multi-Dimensional Arrays</h3>
<p>Swag supports multi-dimensional arrays using the syntax '[X, Y, Z...]', where each number represents a dimension.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> array: [<span class="SNum">2</span>, <span class="SNum">2</span>] <span class="STpe">s32</span>
    array[<span class="SNum">0</span>, <span class="SNum">0</span>] = <span class="SNum">1</span>
    array[<span class="SNum">0</span>, <span class="SNum">1</span>] = <span class="SNum">2</span>
    array[<span class="SNum">1</span>, <span class="SNum">0</span>] = <span class="SNum">3</span>
    array[<span class="SNum">1</span>, <span class="SNum">1</span>] = <span class="SNum">4</span>
}

</span></div>
<h3 id="C_C___Style_Nested_Arrays">C/C++ Style Nested Arrays</h3>
<p>Nested array syntax is also accepted, similar to C/C++, and '[i, j]' indexing works on it just as well.</p>
<div class="blockquote blockquote-warning">
<div class="blockquote-title-block"><span class="blockquote-title">Warning</span></div>
<p>The two spellings are <b>not</b> the same type. '[2, 2] s32' is one array with two dimensions, while '[2][2] s32' is a one-dimensional array of '[2] s32'. They do not convert to each other, so pick one spelling per API and keep it.</p>
</div>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> array: [<span class="SNum">2</span>, <span class="SNum">2</span>] <span class="STpe">s32</span>
    array[<span class="SNum">0</span>, <span class="SNum">0</span>] = <span class="SNum">1</span>
    array[<span class="SNum">0</span>, <span class="SNum">1</span>] = <span class="SNum">2</span>
    array[<span class="SNum">1</span>, <span class="SNum">0</span>] = <span class="SNum">3</span>
    array[<span class="SNum">1</span>, <span class="SNum">1</span>] = <span class="SNum">4</span>

    <span class="SCmt">// A different type from 'array', even though it indexes the same way.</span>
    <span class="SKwd">var</span> array1: [<span class="SNum">2</span>][<span class="SNum">2</span>] <span class="STpe">s32</span>
    array1[<span class="SNum">0</span>, <span class="SNum">0</span>] = <span class="SNum">1</span>
    array1[<span class="SNum">0</span>, <span class="SNum">1</span>] = <span class="SNum">2</span>
    array1[<span class="SNum">1</span>, <span class="SNum">0</span>] = <span class="SNum">3</span>
    array1[<span class="SNum">1</span>, <span class="SNum">1</span>] = <span class="SNum">4</span>
}

</span></div>
<h3 id="Array_Size_Deduction">Array Size Deduction</h3>
<p>Swag can infer the dimensions of arrays — including multi-dimensional ones — directly from the initialization expression.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> array  = [<span class="SNum">1</span>, <span class="SNum">2</span>, <span class="SNum">3</span>, <span class="SNum">4</span>]
    <span class="SKwd">var</span> array1 = [[<span class="SNum">1</span>, <span class="SNum">2</span>], [<span class="SNum">3</span>, <span class="SNum">4</span>]]
    <span class="SCmp">#assert</span>(<span class="SItr">@countof</span>(array) == <span class="SNum">4</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">@countof</span>(array1) == <span class="SNum">2</span>)
}

</span></div>
<h3 id="Single_Value_Initialization">Single Value Initialization</h3>
<p>An entire array can be initialized with a single value. This feature applies to variables (not constants) and works for basic types such as integers, floats, strings, booleans, and runes.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> arr: [<span class="SNum">2</span>, <span class="SNum">2</span>] <span class="STpe">bool</span> = <span class="SKwd">true</span>
    <span class="SItr">@assert</span>(arr[<span class="SNum">0</span>, <span class="SNum">0</span>] == <span class="SKwd">true</span>)
    <span class="SItr">@assert</span>(arr[<span class="SNum">1</span>, <span class="SNum">1</span>] == <span class="SKwd">true</span>)
    <span class="SKwd">var</span> arr1: [<span class="SNum">5</span>, <span class="SNum">10</span>] <span class="STpe">string</span> = <span class="SStr">"string"</span>
    <span class="SItr">@assert</span>(arr1[<span class="SNum">0</span>, <span class="SNum">0</span>] == <span class="SStr">"string"</span>)
    <span class="SItr">@assert</span>(arr1[<span class="SNum">4</span>, <span class="SNum">9</span>] == <span class="SStr">"string"</span>)
}

</span></div>
<h3 id="_004_002_slice_swg">Slice</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Slices_in_Swag">Slices in Swag</h3>
<p>A slice provides a dynamic view over a contiguous block of memory. Unlike static arrays, slices can point to different memory regions or subsets of existing data at runtime.</p>
<p>A slice consists of a data pointer and a <span class="code-inline">u64</span> count representing the number of elements. This allows efficient access to large datasets without copying memory.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> a: <span class="SItr">#null</span> [..] <span class="STpe">bool</span>
    <span class="SCmp">#assert</span>(<span class="SItr">#sizeof</span>(a) == <span class="SItr">#sizeof</span>(<span class="SItr">#null</span> *<span class="STpe">void</span>) + <span class="SItr">#sizeof</span>(<span class="STpe">u64</span>))
}

</span></div>
<h3 id="Initializing_Slices">Initializing Slices</h3>
<p>Slices can be initialized directly with array literals. The slice will reference the array’s elements.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> a: <span class="SKwd">const</span> [..] <span class="STpe">u32</span> = [<span class="SNum">10</span>, <span class="SNum">20</span>, <span class="SNum">30</span>, <span class="SNum">40</span>, <span class="SNum">50</span>]
    <span class="SItr">@assert</span>(<span class="SItr">@countof</span>(a) == <span class="SNum">5</span>)
    <span class="SItr">@assert</span>(a[<span class="SNum">0</span>] == <span class="SNum">10</span>)
    <span class="SItr">@assert</span>(a[<span class="SNum">4</span>] == <span class="SNum">50</span>)

    a = [<span class="SNum">1</span>, <span class="SNum">2</span>]
    <span class="SItr">@assert</span>(<span class="SItr">@countof</span>(a) == <span class="SNum">2</span>)
    <span class="SItr">@assert</span>(a[<span class="SNum">0</span>] == <span class="SNum">1</span>)
    <span class="SItr">@assert</span>(a[<span class="SNum">1</span>] == <span class="SNum">2</span>)
}

</span></div>
<h3 id="Accessing_Slice_Data">Accessing Slice Data</h3>
<p>The <span class="code-inline">@dataof</span> intrinsic retrieves the slice’s data address, and <span class="code-inline">@countof</span> returns the number of elements.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> a: <span class="SKwd">const</span> [..] <span class="STpe">u32</span> = [<span class="SNum">10</span>, <span class="SNum">20</span>, <span class="SNum">30</span>, <span class="SNum">40</span>, <span class="SNum">50</span>]
    <span class="SKwd">let</span> count             = <span class="SItr">@countof</span>(a)
    <span class="SKwd">let</span> addr              = <span class="SItr">@dataof</span>(a)

    <span class="SItr">@assert</span>(count == <span class="SNum">5</span>)
    <span class="SItr">@assert</span>(addr[<span class="SNum">0</span>] == <span class="SNum">10</span>)
    <span class="SItr">@assert</span>(addr[<span class="SNum">4</span>] == <span class="SNum">50</span>)

    a = [<span class="SNum">1</span>, <span class="SNum">2</span>]
    <span class="SItr">@assert</span>(<span class="SItr">@countof</span>(a) == <span class="SNum">2</span>)
}

</span></div>
<h3 id="Creating_Slices_with___mkslice_">Creating Slices with <span class="code-inline">@mkslice</span></h3>
<p>The <span class="code-inline">@mkslice</span> intrinsic creates a slice from a pointer and an element count.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> array: [<span class="SNum">4</span>] <span class="STpe">u32</span> = [<span class="SNum">10</span>, <span class="SNum">20</span>, <span class="SNum">30</span>, <span class="SNum">40</span>]

    <span class="SKwd">let</span> slice: [..] <span class="STpe">u32</span> = <span class="SItr">@mkslice</span>(<span class="SKwd">cast</span>([*] <span class="STpe">u32</span>) &amp;array[<span class="SNum">0</span>] + <span class="SNum">2</span>, <span class="SNum">2</span>)
    <span class="SItr">@assert</span>(<span class="SItr">@countof</span>(slice) == <span class="SNum">2</span>)
    <span class="SItr">@assert</span>(slice[<span class="SNum">0</span>] == <span class="SNum">30</span>)
    <span class="SItr">@assert</span>(slice[<span class="SNum">1</span>] == <span class="SNum">40</span>)

    slice[<span class="SNum">0</span>] = <span class="SNum">314</span>
    <span class="SItr">@assert</span>(array[<span class="SNum">2</span>] == <span class="SNum">314</span>)
}

</span></div>
<h3 id="Slicing_Strings">Slicing Strings</h3>
<p>Strings can be sliced, but the result must be declared as <span class="code-inline">const</span> since strings are immutable.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> str                     = <span class="SStr">"string"</span>
    <span class="SKwd">let</span> strSlice: <span class="SKwd">const</span> [..] <span class="STpe">u8</span> = <span class="SItr">@mkslice</span>(<span class="SItr">@dataof</span>(str), <span class="SNum">2</span>)
    <span class="SItr">@assert</span>(strSlice[<span class="SNum">0</span>] == '<span class="SFct">s</span>')
    <span class="SItr">@assert</span>(strSlice[<span class="SNum">1</span>] == '<span class="SFct">t</span>')
}

</span></div>
<h3 id="Slicing_with_a_Range">Slicing with a Range</h3>
<p>Indexing with a range creates a slice directly. The range uses the same <span class="code-inline">to</span> and <span class="code-inline">until</span> keywords as a <span class="code-inline">for</span> loop; <span class="code-inline">[..]</span> is the slice <b>type</b>, not the range operator.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> str   = <span class="SStr">"string"</span>
    <span class="SKwd">let</span> slice = str[<span class="SNum">1</span> <span class="SLgc">to</span> <span class="SNum">3</span>]
    <span class="SItr">@assert</span>(slice == <span class="SStr">"tri"</span>)
}

</span></div>
<h3 id="Inclusive_and_Exclusive_Slicing">Inclusive and Exclusive Slicing</h3>
<p>By default, the upper bound in a slice is inclusive. To exclude it, use <span class="code-inline">until</span> instead of <span class="code-inline">to</span>.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> str   = <span class="SStr">"string"</span>
    <span class="SKwd">let</span> slice = str[<span class="SNum">1</span> <span class="SLgc">until</span> <span class="SNum">3</span>]
    <span class="SItr">@assert</span>(slice == <span class="SStr">"tr"</span>)
}

</span></div>
<h3 id="Empty_Slices">Empty Slices</h3>
<p>An <span class="code-inline">until</span> range whose bounds are equal selects nothing and produces an empty slice.</p>
<p>Slicing differs from looping here. A loop asks whether an index is still within a range, so an inverted range simply runs zero times. A slice asks for a <b>length</b>, and an inverted range has none, so it is reported: constant bounds at compile time, computed ones by the <span class="code-inline">Swag.Safety(.BoundCheck)</span> guard, which also checks that the upper bound stays inside the source. Where that guard is off, the count is clamped to zero rather than wrapping, so a slice never describes more memory than its source holds.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> str   = <span class="SStr">"string"</span>
    <span class="SKwd">let</span> empty = str[<span class="SNum">3</span> <span class="SLgc">until</span> <span class="SNum">3</span>]
    <span class="SItr">@assert</span>(<span class="SItr">@countof</span>(empty) == <span class="SNum">0</span>)
    <span class="SItr">@assert</span>(empty == <span class="SStr">""</span>)

    <span class="SKwd">let</span> values = [<span class="SNum">10</span>, <span class="SNum">20</span>, <span class="SNum">30</span>]
    <span class="SItr">@assert</span>(<span class="SItr">@countof</span>(values[<span class="SNum">0</span> <span class="SLgc">until</span> <span class="SNum">0</span>]) == <span class="SNum">0</span>)
    <span class="SItr">@assert</span>(<span class="SItr">@countof</span>(values[<span class="SNum">3</span> <span class="SLgc">until</span> <span class="SNum">3</span>]) == <span class="SNum">0</span>)
}

</span></div>
<h3 id="Slicing_to_the_End">Slicing to the End</h3>
<p>Omitting the upper bound creates a slice extending to the end of the sequence.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> str   = <span class="SStr">"string"</span>
    <span class="SKwd">let</span> slice = str[<span class="SNum">2</span> <span class="SLgc">to</span>]
    <span class="SItr">@assert</span>(slice == <span class="SStr">"ring"</span>)
}

</span></div>
<h3 id="Slicing_from_the_Start">Slicing from the Start</h3>
<p>Omitting the lower bound starts the slice from index 0.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> str = <span class="SStr">"string"</span>

    <span class="SKwd">let</span> slice = str[<span class="SLgc">to</span> <span class="SNum">2</span>]
    <span class="SItr">@assert</span>(slice == <span class="SStr">"str"</span>)

    <span class="SKwd">let</span> slice1 = str[<span class="SLgc">until</span> <span class="SNum">2</span>]
    <span class="SItr">@assert</span>(slice1 == <span class="SStr">"st"</span>)
}

</span></div>
<h3 id="Slicing_Arrays">Slicing Arrays</h3>
<p>Arrays can be sliced the same way as strings.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> arr   = [<span class="SNum">10</span>, <span class="SNum">20</span>, <span class="SNum">30</span>, <span class="SNum">40</span>]
    <span class="SKwd">let</span> slice = arr[<span class="SNum">2</span> <span class="SLgc">to</span> <span class="SNum">3</span>]
    <span class="SItr">@assert</span>(slice[<span class="SNum">0</span>] == <span class="SNum">30</span>)
    <span class="SItr">@assert</span>(slice[<span class="SNum">1</span>] == <span class="SNum">40</span>)
    <span class="SItr">@assert</span>(<span class="SItr">@countof</span>(slice) == <span class="SNum">2</span>)
    <span class="SKwd">let</span> slice1 = arr[<span class="SLgc">to</span>]
    <span class="SItr">@assert</span>(<span class="SItr">@countof</span>(slice1) == <span class="SItr">@countof</span>(arr))
}

</span></div>
<h3 id="Slicing_a_Slice">Slicing a Slice</h3>
<p>A slice can be further sliced to produce another slice.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> arr    = [<span class="SNum">10</span>, <span class="SNum">20</span>, <span class="SNum">30</span>, <span class="SNum">40</span>]
    <span class="SKwd">let</span> slice1 = arr[<span class="SNum">1</span> <span class="SLgc">to</span> <span class="SNum">3</span>]
    <span class="SItr">@assert</span>(slice1[<span class="SNum">0</span>] == <span class="SNum">20</span>)
    <span class="SItr">@assert</span>(slice1[<span class="SNum">1</span>] == <span class="SNum">30</span>)
    <span class="SItr">@assert</span>(slice1[<span class="SNum">2</span>] == <span class="SNum">40</span>)
    <span class="SKwd">let</span> slice2 = slice1[<span class="SNum">1</span> <span class="SLgc">to</span> <span class="SNum">2</span>]
    <span class="SItr">@assert</span>(slice2[<span class="SNum">0</span>] == <span class="SNum">30</span>)
    <span class="SItr">@assert</span>(slice2[<span class="SNum">1</span>] == <span class="SNum">40</span>)
}

</span></div>
<h3 id="Transforming_a_Pointer_into_a_Slice">Transforming a Pointer into a Slice</h3>
<p>A pointer can be transformed into a slice by specifying a range.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> arr   = [<span class="SNum">10</span>, <span class="SNum">20</span>, <span class="SNum">30</span>, <span class="SNum">40</span>]
    <span class="SKwd">let</span> ptr   = &amp;arr[<span class="SNum">2</span>]
    <span class="SKwd">let</span> slice = ptr[<span class="SNum">0</span> <span class="SLgc">to</span> <span class="SNum">1</span>]
    <span class="SItr">@assert</span>(slice[<span class="SNum">0</span>] == <span class="SNum">30</span>)
    <span class="SItr">@assert</span>(slice[<span class="SNum">1</span>] == <span class="SNum">40</span>)
    <span class="SItr">@assert</span>(<span class="SItr">@countof</span>(slice) == <span class="SNum">2</span>)
}

</span></div>
<h3 id="_004_003_tuple_swg">Tuple</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Tuples_in_Swag">Tuples in Swag</h3>
<p>A tuple represents an anonymous structure (a <i>struct literal</i>) that can group multiple values of different types together without defining a named structure. Tuples are enclosed in curly braces <span class="code-inline">{}</span> and can mix any combination of data types.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> tuple1 = {<span class="SNum">2</span>, <span class="SNum">2</span>}
    <span class="SKwd">let</span> tuple2 = {<span class="SStr">"string"</span>, <span class="SNum">2</span>, <span class="SKwd">true</span>}
}

</span></div>
<h3 id="Accessing_Tuple_Values">Accessing Tuple Values</h3>
<p>Tuple fields are automatically named <span class="code-inline">itemX</span>, where <span class="code-inline">X</span> is the zero-based index of the field.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> tuple = {<span class="SStr">"string"</span>, <span class="SNum">2</span>, <span class="SKwd">true</span>}
    <span class="SItr">@assert</span>(tuple.item0 == <span class="SStr">"string"</span>)
    <span class="SItr">@assert</span>(tuple.item1 == <span class="SNum">2</span>)
    <span class="SItr">@assert</span>(tuple.item2 == <span class="SKwd">true</span>)
}

</span></div>
<h3 id="Named_Fields_in_Tuples">Named Fields in Tuples</h3>
<p>Tuple fields can have explicit names.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> tuple = {x: <span class="SNum">1.0</span>, y: <span class="SNum">2.0</span>}
    <span class="SItr">@assert</span>(tuple.x == <span class="SNum">1.0</span>)
    <span class="SItr">@assert</span>(tuple.y == <span class="SNum">2.0</span>)
}

</span></div>
<h3 id="Automatic_Field_Naming">Automatic Field Naming</h3>
<p>When creating a tuple from variables, Swag automatically uses the variable names as field names unless overridden.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> x = <span class="SNum">555</span>
    <span class="SKwd">let</span> y = <span class="SNum">666</span>
    <span class="SKwd">let</span> t = {x, y}
    <span class="SItr">@assert</span>(t.x == <span class="SNum">555</span>)
    <span class="SItr">@assert</span>(t.y == <span class="SNum">666</span>)
}

</span></div>
<h3 id="Tuple_Assignment_and_Compatibility">Tuple Assignment and Compatibility</h3>
<p>Tuples can be assigned to each other if their field types match, even if field names differ.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> x:
    {
        a: <span class="STpe">s32</span>, b: <span class="STpe">s32</span>
    }
    <span class="SKwd">var</span> y:
    {
        c: <span class="STpe">s32</span>, d: <span class="STpe">s32</span>
    }

    y = {<span class="SNum">1</span>, <span class="SNum">2</span>}
    x = y

    <span class="SItr">@assert</span>(x.a == <span class="SNum">1</span>)
    <span class="SItr">@assert</span>(x.b == <span class="SNum">2</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(x) != <span class="SItr">#typeof</span>(y))
}

</span></div>
<h3 id="Positional_Tuple_Destructuring">Positional Tuple Destructuring</h3>
<p>Curly-braced patterns destructure tuple fields by position. A positional pattern provides one binding or placeholder for every field.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> tuple1           = {x: <span class="SNum">1.0</span>, y: <span class="SNum">2.0</span>}
    <span class="SKwd">let</span> {value0, value1} = tuple1
    <span class="SItr">@assert</span>(value0 == <span class="SNum">1.0</span>)
    <span class="SItr">@assert</span>(value1 == <span class="SNum">2.0</span>)

    <span class="SKwd">let</span> tuple2        = {<span class="SStr">"name"</span>, <span class="SKwd">true</span>}
    <span class="SKwd">let</span> {name, value} = tuple2
    <span class="SItr">@assert</span>(name == <span class="SStr">"name"</span>)
    <span class="SItr">@assert</span>(value == <span class="SKwd">true</span>)
}

</span></div>
<h3 id="Ignoring_Fields_During_Positional_Destructuring">Ignoring Fields During Positional Destructuring</h3>
<p>Use <span class="code-inline">?</span> as a placeholder to ignore a field.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> tuple1 = {x: <span class="SNum">1.0</span>, y: <span class="SNum">2.0</span>}
    <span class="SKwd">let</span> {x, ?} = tuple1
    <span class="SItr">@assert</span>(x == <span class="SNum">1.0</span>)

    <span class="SKwd">let</span> {?, y} = tuple1
    <span class="SItr">@assert</span>(y == <span class="SNum">2.0</span>)
}

</span></div>
<h3 id="Named_Tuple_Destructuring">Named Tuple Destructuring</h3>
<p>Write 'field: binding' to select fields by name. Named patterns can select a subset of the fields and can list them in any order. Every entry in one pattern uses the same mode: positional and named entries cannot be mixed.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> point                        = {x: <span class="SNum">10.0</span>, y: <span class="SNum">20.0</span>}
    <span class="SKwd">let</span> {y: vertical, x: horizontal} = point
    <span class="SItr">@assert</span>(horizontal == <span class="SNum">10.0</span>)
    <span class="SItr">@assert</span>(vertical == <span class="SNum">20.0</span>)

    <span class="SKwd">let</span> {x: onlyX} = point
    <span class="SItr">@assert</span>(onlyX == <span class="SNum">10.0</span>)
}

</span></div>
<p>Unnamed tuple fields retain their implicit <span class="code-inline">itemN</span> names. This also applies when explicit and unnamed fields appear in either order.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> namedThenUnnamed          = {x: <span class="SNum">11</span>, <span class="SNum">22</span>}
    <span class="SKwd">let</span> {x: first, item1: second} = namedThenUnnamed
    <span class="SItr">@assert</span>(first == <span class="SNum">11</span>)
    <span class="SItr">@assert</span>(second == <span class="SNum">22</span>)

    <span class="SKwd">let</span> unnamedThenNamed          = {<span class="SNum">33</span>, y: <span class="SNum">44</span>}
    <span class="SKwd">let</span> {item0: third, y: fourth} = unnamedThenNamed
    <span class="SItr">@assert</span>(third == <span class="SNum">33</span>)
    <span class="SItr">@assert</span>(fourth == <span class="SNum">44</span>)
}

</span></div>
<h3 id="Destructuring_Assignment">Destructuring Assignment</h3>
<p>The same positional and named patterns can assign to existing storage.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> first, second: <span class="STpe">s32</span>
    {first, second} = {<span class="SNum">1</span>, <span class="SNum">2</span>}
    <span class="SItr">@assert</span>(first == <span class="SNum">1</span>)
    <span class="SItr">@assert</span>(second == <span class="SNum">2</span>)

    <span class="SKwd">var</span> point = {x: <span class="SNum">3</span>, y: <span class="SNum">4</span>}
    {y: second, x: first} = point
    <span class="SItr">@assert</span>(first == <span class="SNum">3</span>)
    <span class="SItr">@assert</span>(second == <span class="SNum">4</span>)
}

</span></div>
<h3 id="_004_004_enum_swg">Enum</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Enums_in_Swag">Enums in Swag</h3>
<p>Enums define a set of named constant values. Unlike C/C++, Swag allows enum values to end with <span class="code-inline">;</span>, <span class="code-inline">,</span>, or simply a new line.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">enum</span> <span class="SCst">Values0</span> { <span class="SCst">A</span>, <span class="SCst">B</span> }
    <span class="SKwd">enum</span> <span class="SCst">Values1</span> { <span class="SCst">A</span>, <span class="SCst">B</span> }
    <span class="SKwd">enum</span> <span class="SCst">Values2</span> { <span class="SCst">A</span>, <span class="SCst">B</span> }
    <span class="SKwd">enum</span> <span class="SCst">Values3</span> { <span class="SCst">A</span>, <span class="SCst">B</span> }
}

</span></div>
<h3 id="Enum_Underlying_Type">Enum Underlying Type</h3>
<p>By default, enums use the <span class="code-inline">s32</span> type for storage.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">enum</span> <span class="SCst">Values</span> { <span class="SCst">A</span>, <span class="SCst">B</span> }
    <span class="SKwd">let</span> type = <span class="SItr">#typeof</span>(<span class="SCst">Values</span>)
    <span class="SItr">@assert</span>(type.rawType == <span class="STpe">s32</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(<span class="SCst">Values</span>) == <span class="SCst">Values</span>)
}

</span></div>
<h3 id="Custom_Enum_Underlying_Type">Custom Enum Underlying Type</h3>
<p>A custom base type can be specified after the enum name.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">enum</span> <span class="SCst">Values1</span>: <span class="STpe">s64</span>
    {
        <span class="SCst">A</span>
        <span class="SCst">B</span>
        <span class="SCst">C</span>
    }

    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(<span class="SCst">Values1</span>).rawType == <span class="STpe">s64</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(<span class="SCst">Values1</span>.<span class="SCst">A</span>) == <span class="SCst">Values1</span>)
}

</span></div>
<h3 id="Default_and_Custom_Enum_Values">Default and Custom Enum Values</h3>
<p>Without explicit values, enums start at 0 and increment by 1.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">enum</span> <span class="SCst">Value</span>: <span class="STpe">s64</span> { <span class="SCst">A</span>, <span class="SCst">B</span>, <span class="SCst">C</span> }
    <span class="SCmp">#assert</span>(<span class="SCst">Value</span>.<span class="SCst">A</span> == <span class="SNum">0</span>)
    <span class="SCmp">#assert</span>(<span class="SCst">Value</span>.<span class="SCst">B</span> == <span class="SNum">1</span>)
    <span class="SCmp">#assert</span>(<span class="SCst">Value</span>.<span class="SCst">C</span> == <span class="SNum">2</span>)
}

</span></div>
<p>Custom values can be assigned manually.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">enum</span> <span class="SCst">Value</span>: <span class="STpe">s64</span> { <span class="SCst">A</span> = <span class="SNum">10</span>, <span class="SCst">B</span> = <span class="SNum">20</span>, <span class="SCst">C</span> = <span class="SNum">30</span> }
    <span class="SCmp">#assert</span>(<span class="SCst">Value</span>.<span class="SCst">A</span> == <span class="SNum">10</span>)
    <span class="SCmp">#assert</span>(<span class="SCst">Value</span>.<span class="SCst">B</span> == <span class="SNum">20</span>)
    <span class="SCmp">#assert</span>(<span class="SCst">Value</span>.<span class="SCst">C</span> == <span class="SNum">30</span>)
}

</span></div>
<h3 id="Incremental_Enum_Values">Incremental Enum Values</h3>
<p>After a custom value, following values auto-increment.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">enum</span> <span class="SCst">Value</span>: <span class="STpe">u32</span>
    {
        <span class="SCst">A</span> = <span class="SNum">10</span>
        <span class="SCst">B</span>
        <span class="SCst">C</span>
    }

    <span class="SCmp">#assert</span>(<span class="SCst">Value</span>.<span class="SCst">A</span> == <span class="SNum">10</span>)
    <span class="SCmp">#assert</span>(<span class="SCst">Value</span>.<span class="SCst">B</span> == <span class="SNum">11</span>)
    <span class="SCmp">#assert</span>(<span class="SCst">Value</span>.<span class="SCst">C</span> == <span class="SNum">12</span>)
}

</span></div>
<h3 id="Non-Integer_Enum_Values">Non-Integer Enum Values</h3>
<p>Non-integer enums require explicit assignments.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">enum</span> <span class="SCst">Value1</span>: <span class="STpe">string</span> { <span class="SCst">A</span> = <span class="SStr">"string 1"</span>, <span class="SCst">B</span> = <span class="SStr">"string 2"</span>, <span class="SCst">C</span> = <span class="SStr">"string 3"</span> }
    <span class="SCmp">#assert</span>(<span class="SCst">Value1</span>.<span class="SCst">A</span> == <span class="SStr">"string 1"</span>)

    <span class="SKwd">enum</span> <span class="SCst">Value2</span>: <span class="STpe">f32</span>
    {
        <span class="SCst">A</span> = <span class="SNum">1.0</span>
        <span class="SCst">B</span> = <span class="SNum">3.14</span>
        <span class="SCst">C</span> = <span class="SNum">6.0</span>
    }

    <span class="SCmp">#assert</span>(<span class="SItr">@abs</span>(<span class="SKwd">cast</span>(<span class="STpe">f32</span>) <span class="SCst">Value2</span>.<span class="SCst">B</span> - <span class="SNum">3.14</span>) &lt; <span class="SNum">0.001</span>)
}

</span></div>
<h3 id="Counting_Enum_Values">Counting Enum Values</h3>
<p><span class="code-inline">@countof</span> returns the number of enum members.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">enum</span> <span class="SCst">Value</span>: <span class="STpe">string</span>
    {
        <span class="SCst">A</span> = <span class="SStr">"1"</span>
        <span class="SCst">B</span> = <span class="SStr">"2"</span>
        <span class="SCst">C</span> = <span class="SStr">"3"</span>
    }

    <span class="SItr">@assert</span>(<span class="SItr">@countof</span>(<span class="SCst">Value</span>) == <span class="SNum">3</span>)
}

</span></div>
<h3 id="Using__using__with_Enums">Using <span class="code-inline">using</span> with Enums</h3>
<p><span class="code-inline">using</span> allows direct access to enum values without prefixing with the enum name.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">enum</span> <span class="SCst">Value</span> { <span class="SCst">A</span>, <span class="SCst">B</span>, <span class="SCst">C</span> }
    <span class="SKwd">using</span> <span class="SCst">Value</span>

    <span class="SItr">@assert</span>(<span class="SCst">A</span> == <span class="SNum">0</span>)
    <span class="SItr">@assert</span>(<span class="SCst">B</span> == <span class="SNum">1</span>)
    <span class="SItr">@assert</span>(<span class="SCst">Value</span>.<span class="SCst">C</span> == <span class="SNum">2</span>)
}

</span></div>
<h3 id="Enums_as_Flags">Enums as Flags</h3>
<p>With <span class="code-inline">#[Swag.EnumFlags]</span>, enum values represent bit flags. They should use unsigned integer types.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SAtr">#[Swag.EnumFlags]</span>
    <span class="SKwd">enum</span> <span class="SCst">MyFlags</span>: <span class="STpe">u8</span> { <span class="SCst">A</span>, <span class="SCst">B</span>, <span class="SCst">C</span>, <span class="SCst">D</span> }

    <span class="SCmp">#assert</span>(<span class="SCst">MyFlags</span>.<span class="SCst">A</span> == <span class="SNum">0b00000001</span>)
    <span class="SCmp">#assert</span>(<span class="SCst">MyFlags</span>.<span class="SCst">B</span> == <span class="SNum">0b00000010</span>)
    <span class="SCmp">#assert</span>(<span class="SCst">MyFlags</span>.<span class="SCst">C</span> == <span class="SNum">0b00000100</span>)

    <span class="SKwd">let</span> value = <span class="SCst">MyFlags</span>.<span class="SCst">B</span> | <span class="SCst">MyFlags</span>.<span class="SCst">C</span>
    <span class="SItr">@assert</span>(value == <span class="SNum">0b00000110</span>)
}

</span></div>
<h3 id="Enums_with_Arrays">Enums with Arrays</h3>
<p>Enums can store array constants.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">enum</span> <span class="SCst">Value</span>: <span class="SKwd">const</span> [<span class="SNum">2</span>] <span class="STpe">s32</span> { <span class="SCst">A</span> = [<span class="SNum">1</span>, <span class="SNum">2</span>], <span class="SCst">B</span> = [<span class="SNum">10</span>, <span class="SNum">20</span>] }
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(<span class="SCst">Value</span>).rawType == <span class="SKwd">const</span> [<span class="SNum">2</span>] <span class="STpe">s32</span>)
}

</span></div>
<h3 id="Enums_with_Slices">Enums with Slices</h3>
<p>Enums can also store slices.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">enum</span> <span class="SCst">Value</span>: <span class="SKwd">const</span> [..] <span class="STpe">s32</span> { <span class="SCst">A</span> = [<span class="SNum">1</span>, <span class="SNum">2</span>], <span class="SCst">B</span> = [<span class="SNum">10</span>, <span class="SNum">20</span>, <span class="SNum">30</span>] }
    <span class="SKwd">let</span> a = <span class="SKwd">cast</span>(<span class="SKwd">const</span> [..] <span class="STpe">s32</span>) <span class="SCst">Value</span>.<span class="SCst">A</span>
    <span class="SKwd">let</span> b = <span class="SKwd">cast</span>(<span class="SKwd">const</span> [..] <span class="STpe">s32</span>) <span class="SCst">Value</span>.<span class="SCst">B</span>
    <span class="SCmp">#assert</span>(<span class="SItr">@countof</span>(a) == <span class="SNum">2</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">@countof</span>(b) == <span class="SNum">3</span>)
    <span class="SItr">@assert</span>(b[<span class="SNum">2</span>] == <span class="SNum">30</span>)
}

</span></div>
<h3 id="Importing_Enum_Values">Importing Enum Values</h3>
<p>Enums can import values from another enum using <span class="code-inline">using</span>. Both enums must share the same base type.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">enum</span> <span class="SCst">BasicErrors</span> { <span class="SCst">FailedToLoad</span>, <span class="SCst">FailedToSave</span> }

<span class="SKwd">enum</span> <span class="SCst">MyErrors</span>
{
    <span class="SKwd">using</span> <span class="SCst">BasicErrors</span>
    <span class="SCst">NotFound</span> = <span class="SNum">100</span>
}

</span></div>
<h3 id="Accessing_Imported_Enum_Values">Accessing Imported Enum Values</h3>
<p>Imported enum values are available through the parent enum scope and keep their original enum type.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">MyError0</span> = <span class="SCst">MyErrors</span>.<span class="SCst">FailedToSave</span>

<span class="SFct">#test</span>
{
    <span class="SKwd">const</span> <span class="SCst">E0</span>: <span class="SCst">BasicErrors</span> = <span class="SCst">MyErrors</span>.<span class="SCst">FailedToLoad</span>
    <span class="SKwd">const</span> <span class="SCst">E1</span>: <span class="SCst">BasicErrors</span> = <span class="SCst">BasicErrors</span>.<span class="SCst">FailedToLoad</span>

    <span class="SKwd">func</span> <span class="SFct">toto</span>(err: <span class="SCst">BasicErrors</span>)
    {
        <span class="SItr">@assert</span>(err == <span class="SCst">BasicErrors</span>.<span class="SCst">FailedToLoad</span>)
    }

    <span class="SFct">toto</span>(<span class="SCst">E0</span>)
    <span class="SFct">toto</span>(<span class="SCst">E1</span>)
}

</span></div>
<h3 id="Enum-indexed_Arrays">Enum-indexed Arrays</h3>
<p>An enum can define the index domain of an array. Its values must be unique integers forming the contiguous range from zero to the last value.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">enum</span> <span class="SCst">MyIndex</span> { <span class="SCst">First</span>, <span class="SCst">Second</span>, <span class="SCst">Third</span> }

    <span class="SKwd">const</span> <span class="SCst">Array</span>: [<span class="SCst">MyIndex</span>] <span class="STpe">s32</span> = [<span class="SNum">0</span>, <span class="SNum">1</span>, <span class="SNum">2</span>]
    <span class="SKwd">const</span> <span class="SCst">Valu</span>                 = <span class="SCst">Array</span>[<span class="SCst">MyIndex</span>.<span class="SCst">First</span>]
    <span class="SItr">@assert</span>(<span class="SCst">Valu</span> == <span class="SNum">0</span>)

    <span class="SKwd">var</span> index = <span class="SCst">MyIndex</span>.<span class="SCst">Third</span>
    <span class="SItr">@assert</span>(<span class="SCst">Array</span>[index] == <span class="SNum">2</span>)
}

</span></div>
<h3 id="Specific_Enum_Attributes">Specific Enum Attributes</h3>
<p><span class="code-inline">#[Swag.NoDuplicate]</span> prevents duplicate values.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SAtr">#[Swag.NoDuplicate]</span>
    <span class="SKwd">enum</span> <span class="SCst">MyEnum</span> { <span class="SCst">Val0</span> = <span class="SNum">0</span> }
}

</span></div>
<h3 id="Enum_Type_Inference">Enum Type Inference</h3>
<p>Swag infers enum types automatically in assignments and expressions.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">enum</span> <span class="SCst">Values</span> { <span class="SCst">A</span>, <span class="SCst">B</span> }
    <span class="SKwd">let</span> x: <span class="SCst">Values</span> = <span class="SCst">Values</span>.<span class="SCst">A</span>
    <span class="SKwd">let</span> y: <span class="SCst">Values</span> = .<span class="SCst">A</span>
    <span class="SItr">@assert</span>(x == y)
}

</span></div>
<h3 id="Type_Inference_in__switch_">Type Inference in <span class="code-inline">switch</span></h3>
<p>Enum types are inferred inside <span class="code-inline">switch</span> statements. A case value uses the same auto-scope syntax as any other inferred enum value: keep the leading dot. The bare form <span class="code-inline">case A</span> does not implicitly enter the enum scope.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">enum</span> <span class="SCst">Values</span> { <span class="SCst">A</span>, <span class="SCst">B</span> }
    <span class="SKwd">let</span> x = <span class="SCst">Values</span>.<span class="SCst">A</span>

    <span class="SLgc">switch</span> x
    {
    <span class="SLgc">case</span> .<span class="SCst">A</span>: <span class="SLgc">break</span>
    <span class="SLgc">case</span> .<span class="SCst">B</span>: <span class="SLgc">break</span>
    }
}

</span></div>
<h3 id="Simplified_Enum_Syntax">Simplified Enum Syntax</h3>
<p>You can omit the enum name when the type is already known.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">enum</span> <span class="SCst">Values</span> { <span class="SCst">A</span>, <span class="SCst">B</span> }
    <span class="SKwd">let</span> x = <span class="SCst">Values</span>.<span class="SCst">A</span>
    <span class="SItr">@assert</span>(x == .<span class="SCst">A</span>)
}

</span></div>
<h3 id="Simplified_Enum_Flags_Syntax">Simplified Enum Flags Syntax</h3>
<p>This works with flags too.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SAtr">#[Swag.EnumFlags]</span>
    <span class="SKwd">enum</span> <span class="SCst">Values</span> { <span class="SCst">A</span>, <span class="SCst">B</span> }

    <span class="SKwd">let</span> x = <span class="SCst">Values</span>.<span class="SCst">A</span> | <span class="SCst">Values</span>.<span class="SCst">B</span>
    <span class="SItr">@assert</span>((x &amp; .<span class="SCst">A</span>) <span class="SLgc">and</span> (x &amp; .<span class="SCst">B</span>))
}

</span></div>
<h3 id="Simplified_Enum_Syntax_in_Functions">Simplified Enum Syntax in Functions</h3>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">enum</span> <span class="SCst">Values</span> { <span class="SCst">A</span>, <span class="SCst">B</span> }
    <span class="SKwd">func</span> <span class="SFct">toto</span>(v1, v2: <span class="SCst">Values</span>) {}
    <span class="SFct">toto</span>(.<span class="SCst">A</span>, .<span class="SCst">B</span>)
}

</span></div>
<h3 id="Iterating_Over_Enum_Values">Iterating Over Enum Values</h3>
<p>You can loop over the number of enum values with <span class="code-inline">for</span>, or iterate the values themselves by binding a name.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">enum</span> <span class="SCst">RGB</span> { <span class="SCst">R</span>, <span class="SCst">G</span>, <span class="SCst">B</span> }
    <span class="SKwd">var</span> cpt = <span class="SNum">0</span>
    <span class="SLgc">for</span> <span class="SCst">RGB</span> <span class="SLgc">do</span>
        cpt += <span class="SNum">1</span>
    <span class="SItr">@assert</span>(cpt == <span class="SNum">3</span>)
}

</span></div>
<p>Binding a name offers a structured way to iterate and handle specific values.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">enum</span> <span class="SCst">RGB</span> { <span class="SCst">R</span>, <span class="SCst">G</span>, <span class="SCst">B</span> }
    <span class="SLgc">for</span> val <span class="SLgc">in</span> <span class="SCst">RGB</span>
    {
        <span class="SLgc">switch</span> val
        {
        <span class="SLgc">case</span> .<span class="SCst">R</span>: <span class="SLgc">break</span>
        <span class="SLgc">case</span> .<span class="SCst">G</span>: <span class="SLgc">break</span>
        <span class="SLgc">case</span> .<span class="SCst">B</span>: <span class="SLgc">break</span>
        <span class="SLgc">default</span>: <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
        }
    }
}

</span></div>
<h3 id="_004_005_impl_swg">Impl</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Implementing_Methods_for_Enums_in_Swag">Implementing Methods for Enums in Swag</h3>
<p>Swag allows the use of the <span class="code-inline">impl</span> keyword with enums to define methods directly associated with them. This makes it possible to attach behavior to enum values, enhancing code organization and encapsulation.</p>
<p>Within these methods, the <span class="code-inline">me</span> keyword refers to the current enum instance, similar to <span class="code-inline">this</span> in other languages.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">enum</span> <span class="SCst">RGB</span>
{
    <span class="SCst">R</span>     <span class="SCmt">// Represents Red</span>
    <span class="SCst">G</span>     <span class="SCmt">// Represents Green</span>
    <span class="SCst">B</span>     <span class="SCmt">// Represents Blue</span>
}

</span></div>
<h3 id="Defining_Enum_Methods_with__impl_">Defining Enum Methods with <span class="code-inline">impl</span></h3>
<p>The <span class="code-inline">impl</span> block defines methods that operate on enum values. This helps group functionality logically with the type it belongs to.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">impl</span> <span class="SCst">RGB</span>
{
    <span class="SCmt">// Check if the current color is Red</span>
    <span class="SKwd">func</span> <span class="SFct">isRed</span>(<span class="STpe">me</span>) =&gt; <span class="STpe">me</span> == <span class="SCst">R</span>

    <span class="SCmt">// Check if the current color is Red or Blue</span>
    <span class="SKwd">func</span> <span class="SFct">isRedOrBlue</span>(<span class="STpe">me</span>) =&gt; <span class="STpe">me</span> == <span class="SCst">R</span> <span class="SLgc">or</span> <span class="STpe">me</span> == <span class="SCst">B</span>
}

<span class="SFct">#test</span>
{
    <span class="SCmt">// Verify if `RGB.R` is recognized as red</span>
    <span class="SItr">@assert</span>(<span class="SCst">RGB</span>.<span class="SFct">isRed</span>(<span class="SCst">RGB</span>.<span class="SCst">R</span>))

    <span class="SCmt">// Verify if `RGB.B` is recognized as either red or blue</span>
    <span class="SItr">@assert</span>(<span class="SCst">RGB</span>.<span class="SFct">isRedOrBlue</span>(<span class="SCst">RGB</span>.<span class="SCst">B</span>))
}

</span></div>
<h3 id="Simplifying_Calls_with__using_">Simplifying Calls with <span class="code-inline">using</span></h3>
<p>The <span class="code-inline">using</span> keyword allows you to call enum methods without qualifying them with the enum name. This makes the code cleaner when the enum type is already in scope.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">using</span> <span class="SCst">RGB</span>

    <span class="SItr">@assert</span>(<span class="SFct">isRedOrBlue</span>(<span class="SCst">R</span>))
    <span class="SItr">@assert</span>(<span class="SFct">isRedOrBlue</span>(<span class="SCst">B</span>))
}

</span></div>
<h3 id="Uniform_Function_Call_Syntax__UFCS_">Uniform Function Call Syntax (UFCS)</h3>
<p>Swag supports <i>Uniform Function Call Syntax (UFCS)</i>, meaning methods can be called directly on enum values. This provides a natural, object-oriented style of method invocation.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">using</span> <span class="SCst">RGB</span>

    <span class="SCmt">// Call `isRedOrBlue` directly on the enum value</span>
    <span class="SItr">@assert</span>(<span class="SCst">R</span>.<span class="SFct">isRedOrBlue</span>())

    <span class="SCmt">// Verify that `G` is not recognized as red or blue</span>
    <span class="SItr">@assert</span>(!<span class="SCst">G</span>.<span class="SFct">isRedOrBlue</span>())
}

</span></div>
<h3 id="_004_006_union_swg">Union</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="The__union__Type_in_Swag">The <span class="code-inline">union</span> Type in Swag</h3>
<p>A <span class="code-inline">union</span> is a special kind of struct where all fields share the same memory location. Each field starts at offset <span class="code-inline">0</span>, allowing multiple variables to overlap in memory.</p>
<p>This makes it possible to represent different data types using the same storage space, which is particularly useful for optimizing memory when only one field is used at a time.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SCmt">// Define a union with three overlapping f32 fields: x, y, and z</span>
    <span class="SKwd">union</span> <span class="SCst">MyUnion</span>
    {
        x, y, z: <span class="STpe">f32</span>
    }

    <span class="SCmt">// Initialize the union, setting the value of the 'x' field</span>
    <span class="SKwd">let</span> v = <span class="SCst">MyUnion</span>{x: <span class="SNum">666</span>}

    <span class="SCmt">// All fields share the same memory location â updating one affects all</span>
    <span class="SItr">@assert</span>(v.y == <span class="SNum">666</span>)
    <span class="SItr">@assert</span>(v.z == <span class="SNum">666</span>)
}

</span></div>
<h3 id="How_Unions_Work">How Unions Work</h3>
<p>In this example, the <span class="code-inline">MyUnion</span> type defines three fields (<span class="code-inline">x</span>, <span class="code-inline">y</span>, and <span class="code-inline">z</span>) that occupy the same memory space. Writing to one field overwrites the others, since they are all stored at the same offset.</p>
<p>This design is ideal for cases where different data types (or values) are stored alternately in the same memory area. Here, since all fields are of type <span class="code-inline">f32</span>, assigning a value to <span class="code-inline">x</span> automatically updates <span class="code-inline">y</span> and <span class="code-inline">z</span>, demonstrating the shared-memory behavior of unions.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_004_007_pointers_swg">Pointers</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Single-Value_Pointers">Single-Value Pointers</h3>
<p>A pointer to a <b>single element</b> is declared using the <span class="code-inline">*</span> symbol. It represents the memory address of one instance of a given type.</p>
<p>Pointers can reference any type of data and are fundamental for efficient memory access and manipulation.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> ptr1: <span class="SItr">#null</span> *<span class="STpe">u8</span>            <span class="SCmt">// Pointer to a single 'u8' value</span>
    <span class="SKwd">var</span> ptr2: <span class="SItr">#null</span> *<span class="SItr">#null</span> *<span class="STpe">u8</span>     <span class="SCmt">// Pointer to another pointer to 'u8'</span>
}

</span></div>
<h3 id="Null_Pointers">Null Pointers</h3>
<p>In Swag, a pointer can be <span class="code-inline">null</span>, meaning it does not refer to any valid memory location. Null pointers are often used to indicate uninitialized or intentionally empty references.</p>
<p>It is good practice to check for null pointers before dereferencing them to avoid runtime errors.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> ptr1: <span class="SItr">#null</span> *<span class="STpe">u8</span>
    <span class="SItr">@assert</span>(ptr1 == <span class="SKwd">null</span>)     <span class="SCmt">// Uninitialized pointers are null by default</span>
}

</span></div>
<h3 id="Non-Null_by_Default">Non-Null by Default</h3>
<p>Nullable-capable types — single-value and block pointers, slices, <span class="code-inline">string</span>, <span class="code-inline">cstring</span>, <span class="code-inline">any</span>, and <span class="code-inline">typeinfo</span> — are non-null by default: a bare <span class="code-inline">*u8</span> or <span class="code-inline">string</span> cannot be initialized with <span class="code-inline">null</span> and has no implicit default. A struct field of such a type must therefore be supplied by an aggregate initializer unless it declares an explicit non-null default. Use <span class="code-inline">#null</span> to opt into nullability when null is part of the intended contract.</p>
<p>A <span class="code-inline">#null</span> value cannot flow into a bare (non-null) slot directly, and it cannot be dereferenced, indexed, member-accessed or called while it is still nullable: every use site needs a proof. Flow narrowing provides it implicitly (a dominating null test such as <span class="code-inline">if p == null do return</span>, <span class="code-inline">if p do ...</span>, or the left side of <span class="code-inline">and</span>/<span class="code-inline">or</span>), <span class="code-inline">notnull</span> asserts it explicitly (a safety check panics at runtime if the value is still null), and <span class="code-inline">?.</span> skips the access entirely when the value is null. Comparisons between <span class="code-inline">#null</span> and bare values of the same type are always allowed. <span class="code-inline">undefined</span> remains an explicit low-level escape hatch and must only be used when the storage is initialized manually before it is read.</p>
<p>A value with <span class="code-inline">opDrop</span> can be consumed with <span class="code-inline">#move</span> only when resetting its moved-from source does not require explicit initialization. Give required fields a default, or use <span class="code-inline">undefined</span> deliberately as the low-level escape hatch described above, before moving a droppable value.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">struct</span> <span class="SCst">NonNullPointerHolder</span>
    {
        ptr: *<span class="STpe">u8</span>
    }

    <span class="SKwd">var</span> value           = <span class="SNum">42</span>'<span class="STpe">u8</span>
    <span class="SKwd">var</span> values          = [<span class="SNum">1</span>, <span class="SNum">2</span>, <span class="SNum">3</span>]
    <span class="SKwd">let</span> ptr:   *<span class="STpe">u8</span>      = &amp;value
    <span class="SKwd">let</span> text:  <span class="STpe">string</span>   = <span class="SStr">"value"</span>
    <span class="SKwd">let</span> slice: [..] <span class="STpe">s32</span> = values
    <span class="SKwd">let</span> holder          = <span class="SCst">NonNullPointerHolder</span>{ptr: &amp;value}

    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(ptr) == *<span class="STpe">u8</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(text) == <span class="STpe">string</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(slice) == [..] <span class="STpe">s32</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(holder.ptr) == *<span class="STpe">u8</span>)
}

</span></div>
<h3 id="Use-Site_Nullability_and_____">Use-Site Nullability and <span class="code-inline">?.</span></h3>
<p>Dereferencing a value whose type is still <span class="code-inline">#null</span> is a compile-time error: the flow must prove the value non-null first. The three sanctioned routes are a dominating null test (flow narrowing), an explicit <span class="code-inline">notnull</span> assertion, and the <span class="code-inline">?.</span> guarded access, which skips the rest of the postfix chain when the tested value is null.</p>
<p>A <span class="code-inline">?.</span> chain whose result is itself nullable-capable (a pointer, string, slice, interface...) simply produces the null outcome in its own type. A chain producing a plain value (an integer, a bool...) cannot carry the null outcome and must hand it to an immediate <span class="code-inline">orelse</span> fallback. A void call through <span class="code-inline">?.</span> is a statement that does nothing when the value is null.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">struct</span> <span class="SCst">OptChainRefDoc</span>
    {
        count: <span class="STpe">s64</span>
        next:  <span class="SItr">#null</span> *<span class="SCst">OptChainRefDoc</span>
    }

    <span class="SKwd">var</span> first:  <span class="SCst">OptChainRefDoc</span>
    <span class="SKwd">var</span> second: <span class="SCst">OptChainRefDoc</span>
    first.count  = <span class="SNum">2</span>
    first.next   = &amp;second
    second.count = <span class="SNum">7</span>

    <span class="SKwd">var</span> p: <span class="SItr">#null</span> *<span class="SCst">OptChainRefDoc</span> = &amp;first

    <span class="SCmt">// Narrowing: the null test dominates the dereference.</span>
    <span class="SLgc">if</span> p != <span class="SKwd">null</span> <span class="SLgc">do</span>
        <span class="SItr">@assert</span>(p.count == <span class="SNum">2</span>)

    <span class="SCmt">// 'notnull' asserts the proof explicitly (panics at runtime if wrong).</span>
    <span class="SKwd">let</span> q = <span class="SKwd">notnull</span> p
    <span class="SItr">@assert</span>(q.count == <span class="SNum">2</span>)

    <span class="SCmt">// '?.' skips the access when null; 'orelse' provides the scalar fallback.</span>
    <span class="SCmt">// 'orelse' binds loosely, so the comparison needs the parentheses.</span>
    <span class="SItr">@assert</span>((p?.count <span class="SLgc">orelse</span> -<span class="SNum">1</span>) == <span class="SNum">2</span>)
    <span class="SItr">@assert</span>((p?.next?.count <span class="SLgc">orelse</span> -<span class="SNum">1</span>) == <span class="SNum">7</span>)

    <span class="SCmt">// A nullable-capable chain result carries the null outcome itself.</span>
    <span class="SKwd">let</span> tail = p?.next
    <span class="SItr">@assert</span>(tail != <span class="SKwd">null</span>)

    p = <span class="SKwd">null</span>
    <span class="SItr">@assert</span>((p?.count <span class="SLgc">orelse</span> -<span class="SNum">1</span>) == -<span class="SNum">1</span>)
    <span class="SItr">@assert</span>(p?.next == <span class="SKwd">null</span>)
}

</span></div>
<h3 id="Deferred_Initialization_with__Swag_Late_">Deferred Initialization with <span class="code-inline">Swag.Late</span></h3>
<p>The <span class="code-inline">Swag.Late</span> attribute declares a <b>non-null</b> field or <b>global variable</b> whose storage starts unset (zero/null) and receives its value later — typically in a <span class="code-inline">#run</span> or <span class="code-inline">#init</span> block, or during setup. It replaces the <span class="code-inline">#null ... = null</span> + <span class="code-inline">notnull</span>-at-every-use pattern for values that are guaranteed to be set before first use but cannot be initialized at their declaration.</p>
<p>The exposed type is non-null, so uses need no <span class="code-inline">notnull</span>; every read is guarded (a runtime null panic when still unset). <span class="code-inline">@isset</span> tests whether the value has been assigned, without reading it. <span class="code-inline">Swag.Late</span> needs a nullable-capable type (pointer, slice, <span class="code-inline">string</span>, <span class="code-inline">cstring</span>, interface, function): it uses the null bit pattern as the <span class="code-inline">unset</span> sentinel. A local or parameter uses <span class="code-inline">= undefined</span> definite assignment instead.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">struct</span> <span class="SCst">LateDocResource</span>
{
    weight: <span class="STpe">s32</span>
}

<span class="SKwd">var</span> g_lateDocStorage: <span class="SCst">LateDocResource</span>

<span class="SAtr">#[Swag.Late]</span>
<span class="SKwd">var</span> g_lateDocResource: *<span class="SCst">LateDocResource</span>     <span class="SCmt">// non-null type, set later</span>

<span class="SFct">#run</span>
{
    g_lateDocStorage.weight = <span class="SNum">5</span>
    g_lateDocResource       = &amp;g_lateDocStorage
}

<span class="SFct">#test</span>
{
    <span class="SCmt">// The type is non-null: no 'notnull', no null test needed at the use site.</span>
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(g_lateDocResource) == *<span class="SCst">LateDocResource</span>)

    <span class="SCmt">// '@isset' confirms it was assigned (in the '#run' above).</span>
    <span class="SItr">@assert</span>(<span class="SItr">@isset</span>(g_lateDocResource))

    <span class="SCmt">// Guarded read yields the value directly.</span>
    <span class="SItr">@assert</span>(g_lateDocResource.weight == <span class="SNum">5</span>)
}

</span></div>
<h3 id="Taking_the_Address_of_a_Variable">Taking the Address of a Variable</h3>
<p>The <span class="code-inline">&amp;</span> operator returns the <b>address</b> of a variable, producing a pointer to it. This allows you to access or modify a variable indirectly via its memory address.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> value = <span class="SNum">1</span>
    <span class="SKwd">let</span> ptr   = &amp;value
    <span class="SItr">@assert</span>(<span class="SItr">#nameof</span>(<span class="SItr">#typeof</span>(ptr)) == <span class="SStr">"*s32"</span>)     <span class="SCmt">// The pointer type matches the variable's type</span>
}

</span></div>
<h3 id="Dereferencing_a_Pointer">Dereferencing a Pointer</h3>
<p>To access the value stored at a pointer’s address, use the <span class="code-inline">dref</span> intrinsic. Dereferencing retrieves the data located at the memory address referenced by the pointer.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> value = <span class="SNum">42</span>
    <span class="SKwd">let</span> ptr   = &amp;value
    <span class="SItr">@assert</span>(<span class="SKwd">dref</span> ptr == <span class="SNum">42</span>)     <span class="SCmt">// Access the value stored at the pointer</span>
}

</span></div>
<h3 id="Pointers_to_Const_Data">Pointers to Const Data</h3>
<p><span class="code-inline">const</span> qualifies the <b>pointed-to data</b>, never the pointer itself. Written just before a <span class="code-inline">*</span>, it makes whatever that <span class="code-inline">*</span> points to read-only, so <span class="code-inline">const *u8</span> is a pointer to a read-only <span class="code-inline">u8</span> and assigning through <span class="code-inline">dref</span> is rejected. The pointer variable stays free to point somewhere else; <span class="code-inline">let</span> is what makes a pointer itself immutable.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> str            = <span class="SStr">"string"</span>
    <span class="SKwd">let</span> ptr: <span class="SKwd">const</span> *<span class="STpe">u8</span> = <span class="SItr">@dataof</span>(str)
    <span class="SItr">@assert</span>(<span class="SKwd">dref</span> ptr == '<span class="SFct">s</span>')     <span class="SCmt">// Reading through the pointer is fine,</span>
<span class="SCmt">// but assigning to 'dref ptr' would be rejected</span>
}

</span></div>
<h3 id="Combining__const__with_Pointers">Combining <span class="code-inline">const</span> with Pointers</h3>
<p>Every <span class="code-inline">*</span> in a type carries its own <span class="code-inline">const</span>, so read-only access is chosen level by level. Read the type from left to right: each <span class="code-inline">const</span> applies to the pointee of the <span class="code-inline">*</span> that follows it, exactly one level down.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> ptr:  <span class="SItr">#null</span> *<span class="SItr">#null</span> <span class="SKwd">const</span> *<span class="STpe">u8</span>           <span class="SCmt">// The 'u8' is read-only, the inner pointer is writable</span>
    <span class="SKwd">var</span> ptr1: <span class="SItr">#null</span> <span class="SKwd">const</span> *<span class="SItr">#null</span> <span class="SKwd">const</span> *<span class="STpe">u8</span>     <span class="SCmt">// Both the inner pointer and the 'u8' are read-only</span>
    <span class="SKwd">var</span> ptr2: <span class="SItr">#null</span> <span class="SKwd">const</span> *<span class="SItr">#null</span> *<span class="STpe">u8</span>           <span class="SCmt">// The inner pointer is read-only, the 'u8' is writable</span>
}

</span></div>
<h3 id="Multi-Value_Pointers">Multi-Value Pointers</h3>
<p>To enable <b>pointer arithmetic</b> or reference <b>contiguous memory blocks</b>, use <span class="code-inline">[*]</span> instead of <span class="code-inline">*</span>.</p>
<p>This type of pointer behaves like a view over multiple elements, allowing indexed access and pointer movement through memory.</p>
<div class="code-block"><span class="SCde"><span class="SAtr">#[Swag.Sanity(Swag.SafetyWhat.All, false)]</span>
<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> ptr: <span class="SItr">#null</span> [*] <span class="STpe">u8</span>     <span class="SCmt">// Pointer to a block of 'u8' values</span>
    ptr = ptr - <span class="SNum">1</span>             <span class="SCmt">// Move the pointer back by one element</span>
}

</span></div>
<h3 id="Pointer_Arithmetic_and_Array_Elements">Pointer Arithmetic and Array Elements</h3>
<p>When taking the address of an array element, the resulting pointer refers to that single element. Cast it to a multi-value pointer when pointer arithmetic is intended.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> arr: [<span class="SNum">4</span>] <span class="STpe">s32</span>
    <span class="SKwd">var</span> ptr = <span class="SKwd">cast</span>([*] <span class="STpe">s32</span>) &amp;arr[<span class="SNum">1</span>]

    <span class="SCmt">// The pointer is treated as a multi-value pointer</span>
    ptr = ptr - <span class="SNum">1</span>
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(ptr) == [*] <span class="STpe">s32</span>)
}

</span></div>
<h3 id="Dereferencing_with_Indexing">Dereferencing with Indexing</h3>
<p>When pointer arithmetic is available, you can dereference a pointer using indexes, just like accessing elements in an array.</p>
<p>This is particularly useful when traversing arrays or buffers via pointers.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> arr = [<span class="SNum">1</span>, <span class="SNum">2</span>, <span class="SNum">3</span>, <span class="SNum">4</span>]
    <span class="SKwd">let</span> ptr = <span class="SKwd">cast</span>([*] <span class="STpe">s32</span>) &amp;arr[<span class="SNum">0</span>]
    <span class="SItr">@assert</span>(<span class="SItr">#typeof</span>(ptr) == [*] <span class="STpe">s32</span>)
    <span class="SKwd">let</span> value1 = ptr[<span class="SNum">0</span>]
    <span class="SItr">@assert</span>(value1 == <span class="SNum">1</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(value1) == <span class="STpe">s32</span>)
    <span class="SKwd">let</span> value2 = ptr[<span class="SNum">1</span>]
    <span class="SItr">@assert</span>(value2 == <span class="SNum">2</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(value2) == <span class="STpe">s32</span>)
    <span class="SKwd">let</span> value = <span class="SKwd">dref</span> ptr
    <span class="SItr">@assert</span>(value == <span class="SNum">1</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(value) == <span class="STpe">s32</span>)
}

</span></div>
<h3 id="_004_008_references_swg">References</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="References_in_Swag">References in Swag</h3>
<p>Swag supports <b>references</b>, which behave like pointers but act syntactically like values. References offer a safer and more convenient way to work with memory addresses, eliminating the need for explicit pointer dereferencing in most cases.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> x = <span class="SNum">42</span>

    <span class="SCmt">// Declare a constant reference to 'x'.</span>
    <span class="SCmt">// Unlike C++, you must explicitly take the address of 'x' to create the reference.</span>
    <span class="SKwd">let</span> myRef: <span class="SKwd">const</span> &amp;<span class="STpe">s32</span> = &amp;x

    <span class="SCmt">// References behave like aliases - no explicit dereferencing is needed.</span>
    <span class="SItr">@assert</span>(myRef == <span class="SNum">42</span>)
}

</span></div>
<h3 id="Assigning_Through_References">Assigning Through References</h3>
<p>Assigning a value to a reference (after initialization) updates the <b>referenced variable</b>, not the reference itself.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> x           = <span class="SNum">42</span>
    <span class="SKwd">var</span> myRef: &amp;<span class="STpe">s32</span> = &amp;x
    <span class="SItr">@assert</span>(myRef == <span class="SNum">42</span>)
    myRef = <span class="SNum">66</span>     <span class="SCmt">// Change the value of 'x' through the reference</span>
    <span class="SItr">@assert</span>(myRef == <span class="SNum">66</span>)
    <span class="SItr">@assert</span>(x == <span class="SNum">66</span>)     <span class="SCmt">// 'x' is updated as well</span>
}

</span></div>
<h3 id="References_Bind_Once">References Bind Once</h3>
<p>A reference is bound to its variable at initialization, and stays bound to it for its whole lifetime. Assigning to the reference always updates the referenced variable, never the reference itself.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> x           = <span class="SNum">1</span>
    <span class="SKwd">var</span> y           = <span class="SNum">1000</span>
    <span class="SKwd">var</span> myRef: &amp;<span class="STpe">s32</span> = &amp;x
    <span class="SItr">@assert</span>(myRef == <span class="SNum">1</span>)
    myRef = <span class="SNum">33</span>
    <span class="SItr">@assert</span>(x == <span class="SNum">33</span>)
    <span class="SItr">@assert</span>(y == <span class="SNum">1000</span>)
}

</span></div>
<h3 id="Passing_References_to_Functions">Passing References to Functions</h3>
<p>Normally, you take the address of a variable to create a reference. However, when passing a <b>const reference</b> to a function, Swag automatically takes the address - even for literals.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SCmt">// Passing a literal directly is allowed for const references</span>
    <span class="SFct">toto</span>(<span class="SNum">4</span>)
}

<span class="SKwd">func</span> <span class="SFct">toto</span>(x: <span class="SKwd">const</span> &amp;<span class="STpe">s32</span>)
{
    <span class="SItr">@assert</span>(x == <span class="SNum">4</span>)

    <span class="SCmt">// A reference is still an address internally</span>
    <span class="SKwd">let</span> ptr = &amp;x
    <span class="SItr">@assert</span>(<span class="SKwd">dref</span> ptr == <span class="SNum">4</span>)
}

</span></div>
<h3 id="Using_References_with_Structs">Using References with Structs</h3>
<p>References are especially useful when working with structs. They allow you to pass entire structures or tuples directly, including literal expressions.</p>
<div class="code-block"><span class="SCde">
<span class="SCmt">// Our first simple struct</span>
<span class="SKwd">struct</span> <span class="SCst">MyStruct</span>
{
    x: <span class="STpe">s32</span>, y: <span class="STpe">s32</span>
}

<span class="SFct">#test</span>
{
    <span class="SFct">titi0</span>({<span class="SNum">1</span>, <span class="SNum">2</span>})
    <span class="SFct">titi1</span>({<span class="SNum">3</span>, <span class="SNum">4</span>})
    <span class="SFct">titi2</span>({<span class="SNum">5</span>, <span class="SNum">6</span>})
}

<span class="SKwd">func</span> <span class="SFct">titi0</span>(param: <span class="SKwd">const</span> &amp;{ x: <span class="STpe">s32</span>, y: <span class="STpe">s32</span> })
{
    <span class="SItr">@assert</span>(param.x == <span class="SNum">1</span>)
    <span class="SItr">@assert</span>(param.y == <span class="SNum">2</span>)
}

</span></div>
<h3 id="Equivalent_Reference_Passing">Equivalent Reference Passing</h3>
<p>Declaring a tuple type or a struct type as a function parameter is <b>equivalent</b> to passing a <b>constant reference</b>.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">titi1</span>(param: { x: <span class="STpe">s32</span>, y: <span class="STpe">s32</span> })
{
    <span class="SItr">@assert</span>(param.x == <span class="SNum">3</span>)
    <span class="SItr">@assert</span>(param.y == <span class="SNum">4</span>)
}

<span class="SKwd">func</span> <span class="SFct">titi2</span>(param: <span class="SCst">MyStruct</span>)
{
    <span class="SItr">@assert</span>(param.x == <span class="SNum">5</span>)
    <span class="SItr">@assert</span>(param.y == <span class="SNum">6</span>)
}

</span></div>
<h3 id="_004_009_any_swg">Any</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="The__any__Type_in_Swag">The <span class="code-inline">any</span> Type in Swag</h3>
<p><span class="code-inline">any</span> is a dynamically typed reference that can point to a value of any concrete type.</p>
<div class="blockquote blockquote-warning">
<div class="blockquote-title-block"><span class="blockquote-title">Warning</span></div>
<p><span class="code-inline">any</span> is <b>not</b> a variant. It holds a reference to an existing value plus its runtime type info.</p>
</div>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> a: <span class="SItr">#null</span> <span class="STpe">any</span>

    <span class="SCmt">// Store an s32 literal value in the 'any'</span>
    a = <span class="SNum">6</span>
    <span class="SItr">@assert</span>(<span class="SKwd">cast</span>(<span class="STpe">s32</span>) a == <span class="SNum">6</span>)

    <span class="SCmt">// Now store a string</span>
    a = <span class="SStr">"string"</span>
    <span class="SItr">@assert</span>(<span class="SKwd">cast</span>(<span class="STpe">string</span>) (<span class="SKwd">notnull</span> a) == <span class="SStr">"string"</span>)

    <span class="SCmt">// Now store a bool</span>
    a = <span class="SKwd">true</span>
    <span class="SItr">@assert</span>(<span class="SKwd">cast</span>(<span class="STpe">bool</span>) a == <span class="SKwd">true</span>)
}

</span></div>
<h3 id="Working_with__any__and_Pointers">Working with <span class="code-inline">any</span> and Pointers</h3>
<p>Use <span class="code-inline">@dataof</span> to access a pointer to the underlying value stored inside <span class="code-inline">any</span>.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> a: <span class="STpe">any</span> = <span class="SNum">6</span>
    <span class="SKwd">let</span> ptr    = <span class="SKwd">cast</span>(<span class="SKwd">const</span> *<span class="STpe">s32</span>) <span class="SItr">@dataof</span>(a)
    <span class="SItr">@assert</span>(<span class="SKwd">dref</span> ptr == <span class="SNum">6</span>)
}

</span></div>
<h3 id="Type_Information_and__any_">Type Information and <span class="code-inline">any</span></h3>
<p><span class="code-inline">#typeof</span> on an <span class="code-inline">any</span> yields <span class="code-inline">any</span> (the reference type). Use <span class="code-inline">@kindof</span> to get the concrete runtime type of the referenced value.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> a: <span class="STpe">any</span> = <span class="SStr">"string"</span>
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(a) == <span class="STpe">any</span>)
    <span class="SItr">@assert</span>(<span class="SItr">@kindof</span>(a) == <span class="STpe">string</span>)

    a = <span class="SKwd">true</span>
    <span class="SItr">@assert</span>(<span class="SItr">@kindof</span>(a) == <span class="STpe">bool</span>)
}

</span></div>
<h3 id="Retrieving_Values_from__any_">Retrieving Values from <span class="code-inline">any</span></h3>
<p>You can retrieve the stored value directly or as a constant reference.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> a: <span class="STpe">any</span> = <span class="SNum">42</span>
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(a) == <span class="STpe">any</span>)
    <span class="SItr">@assert</span>(<span class="SItr">@kindof</span>(a) == <span class="STpe">s32</span>)

    <span class="SKwd">let</span> b = <span class="SKwd">cast</span>(<span class="STpe">s32</span>) a     <span class="SCmt">// Get the value itself</span>
    <span class="SItr">@assert</span>(b == <span class="SNum">42</span>)

    <span class="SKwd">let</span> c = <span class="SKwd">cast</span>(<span class="SKwd">const</span> &amp;<span class="STpe">s32</span>) a     <span class="SCmt">// Get a constant reference to the value</span>
    <span class="SKwd">let</span> d = <span class="SKwd">cast</span>(<span class="SKwd">const</span> *<span class="STpe">s32</span>) a     <span class="SCmt">// Get a constant pointer to the value</span>
    <span class="SItr">@assert</span>(c == <span class="SNum">42</span>)
    <span class="SItr">@assert</span>(<span class="SKwd">dref</span> d == <span class="SNum">42</span>)
}

</span></div>
<h3 id="Arrays_of__any_">Arrays of <span class="code-inline">any</span></h3>
<p>You can create heterogeneous arrays where each element holds a different type.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> array: [?] <span class="STpe">any</span> = [<span class="SKwd">true</span>, <span class="SNum">2</span>, <span class="SNum">3.0</span>, <span class="SStr">"4"</span>]

    <span class="SItr">@assert</span>(<span class="SItr">@kindof</span>(array[<span class="SNum">0</span>]) == <span class="STpe">bool</span>)
    <span class="SItr">@assert</span>(<span class="SItr">@kindof</span>(array[<span class="SNum">1</span>]) == <span class="STpe">s32</span>)
    <span class="SItr">@assert</span>(<span class="SItr">@kindof</span>(array[<span class="SNum">2</span>]) == <span class="STpe">f32</span>)
    <span class="SItr">@assert</span>(<span class="SItr">@kindof</span>(array[<span class="SNum">3</span>]) == <span class="STpe">string</span>)

    <span class="SItr">@assert</span>(<span class="SKwd">cast</span>(<span class="STpe">bool</span>) array[<span class="SNum">0</span>] == <span class="SKwd">true</span>)
    <span class="SItr">@assert</span>(<span class="SKwd">cast</span>(<span class="STpe">s32</span>) array[<span class="SNum">1</span>] == <span class="SNum">2</span>)
    <span class="SItr">@assert</span>(<span class="SKwd">cast</span>(<span class="STpe">f32</span>) array[<span class="SNum">2</span>] == <span class="SNum">3.0</span>)
    <span class="SItr">@assert</span>(<span class="SKwd">cast</span>(<span class="STpe">string</span>) array[<span class="SNum">3</span>] == <span class="SStr">"4"</span>)
}

</span></div>
<h3 id="Nullability_of__any_">Nullability of <span class="code-inline">any</span></h3>
<p>An <span class="code-inline">any</span> value can be null, similar to pointers and other nullable types.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> x: <span class="SItr">#null</span> <span class="STpe">any</span>
    <span class="SItr">@assert</span>(x == <span class="SKwd">null</span>)

    x = <span class="SNum">6</span>
    <span class="SItr">@assert</span>(x != <span class="SKwd">null</span>)
    <span class="SItr">@assert</span>(<span class="SKwd">cast</span>(<span class="STpe">s32</span>) x == <span class="SNum">6</span>)

    x = <span class="SStr">"string"</span>
    <span class="SItr">@assert</span>(x != <span class="SKwd">null</span>)
    <span class="SItr">@assert</span>(<span class="SKwd">cast</span>(<span class="STpe">string</span>) (<span class="SKwd">notnull</span> x) == <span class="SStr">"string"</span>)

    x = <span class="SKwd">null</span>
    <span class="SItr">@assert</span>(x == <span class="SKwd">null</span>)
}

</span></div>
<h3 id="Type_Checking_with__any_">Type Checking with <span class="code-inline">any</span></h3>
<p>An <span class="code-inline">any</span> can be compared to a type using <span class="code-inline">==</span> or <span class="code-inline">!=</span>. This uses <span class="code-inline">@kindof</span> internally to compare the stored value's type.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> x: <span class="SItr">#null</span> <span class="STpe">any</span>
    <span class="SItr">@assert</span>(x == <span class="SKwd">null</span>)

    x = <span class="SNum">6</span>
    <span class="SItr">@assert</span>(x == <span class="STpe">s32</span>)
    <span class="SItr">@assert</span>(x != <span class="STpe">bool</span>)

    x = <span class="SStr">"string"</span>
    <span class="SItr">@assert</span>(x != <span class="STpe">s32</span>)
    <span class="SItr">@assert</span>(x == <span class="STpe">string</span>)

    <span class="SKwd">struct</span> <span class="SCst">A</span> {}
    x = <span class="SCst">A</span>{}
    <span class="SItr">@assert</span>(x == <span class="SCst">A</span>)
}

</span></div>
<h2 id="_005_000_control_flow_swg">Control Flow</h2>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>
</span></div>
<p>Control flow is expression-oriented but explicit. The following sections cover conditional execution, every form of <span class="code-inline">for</span>, element destructuring, <span class="code-inline">while</span>, <span class="code-inline">switch</span>, fallthrough, and labeled <span class="code-inline">break</span>/<span class="code-inline">continue</span>.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_005_001_if_swg">If</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Basic_Usage_of__if_">Basic Usage of <span class="code-inline">if</span></h3>
<p>A basic test with an <span class="code-inline">if</span> statement.</p>
<p>In Swag, curly braces <span class="code-inline">{}</span> are optional for control structures like <span class="code-inline">if</span>. However, if you omit them, you must use <span class="code-inline">do</span>. This rule also applies to <span class="code-inline">while</span> and <span class="code-inline">for</span> loops.</p>
<p>Unlike in C/C++, the condition in an <span class="code-inline">if</span> statement does not need parentheses. They can be used for clarity or grouping, but they are not required.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> a = <span class="SNum">0</span>

    <span class="SLgc">if</span> a == <span class="SNum">1</span> <span class="SLgc">do</span>
        <span class="SItr">@assert</span>(<span class="SKwd">false</span>)

    <span class="SLgc">if</span> a == <span class="SNum">1</span> <span class="SLgc">do</span>
        <span class="SItr">@assert</span>(<span class="SKwd">false</span>)

    <span class="SLgc">if</span> a == <span class="SNum">0</span>
    {
        <span class="SItr">@assert</span>(<span class="SKwd">true</span>)
    }

    <span class="SCmt">// The 'else' keyword works as in most languages.</span>
    <span class="SCmt">// When omitting braces, 'do' is mandatory after the condition.</span>
    <span class="SLgc">if</span> a == <span class="SNum">0</span> <span class="SLgc">do</span>
        a += <span class="SNum">1</span>
    <span class="SLgc">else</span> <span class="SLgc">do</span>
        a += <span class="SNum">2</span>
    <span class="SItr">@assert</span>(a == <span class="SNum">1</span>)

    <span class="SCmt">// 'elif' functions like 'else if' in other languages.</span>
    <span class="SLgc">if</span> a == <span class="SNum">1</span> <span class="SLgc">do</span>
        a += <span class="SNum">1</span>
    <span class="SLgc">else</span> <span class="SLgc">do</span>
        <span class="SLgc">if</span> a == <span class="SNum">2</span> <span class="SLgc">do</span>
            <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    <span class="SLgc">elif</span> a == <span class="SNum">3</span> <span class="SLgc">do</span>
        <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    <span class="SLgc">elif</span> a == <span class="SNum">4</span> <span class="SLgc">do</span>
        <span class="SItr">@assert</span>(<span class="SKwd">false</span>)

    <span class="SCmt">// Logical expressions work as expected with 'and' and 'or'.</span>
    <span class="SLgc">if</span> a == <span class="SNum">0</span> <span class="SLgc">and</span> a == <span class="SNum">1</span> <span class="SLgc">do</span>
        <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    <span class="SLgc">if</span> a == <span class="SNum">0</span> <span class="SLgc">or</span> a == <span class="SNum">1</span> <span class="SLgc">do</span>
        <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    <span class="SLgc">if</span> a == <span class="SNum">1</span> <span class="SLgc">or</span> a == <span class="SNum">2</span> <span class="SLgc">do</span>
        <span class="SItr">@assert</span>(<span class="SKwd">true</span>)
}

</span></div>
<h3 id="Variable_Declaration_in__if_">Variable Declaration in <span class="code-inline">if</span></h3>
<p>You can declare and test a variable directly in an <span class="code-inline">if</span> statement. When doing so, the use of <span class="code-inline">var</span>, <span class="code-inline">let</span>, or <span class="code-inline">const</span> is mandatory.</p>
<p>The declared variable is converted to a boolean for the condition: non-zero (or non-null) values are considered <span class="code-inline">true</span>.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SCmt">// Declare and test 'a' in the same line.</span>
    <span class="SCmt">// Since 'a' is 0, the condition is false and the block will not execute.</span>
    <span class="SLgc">if</span> <span class="SKwd">let</span> a = <span class="SNum">0</span>
    {
        <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    }

    <span class="SCmt">// Redeclare 'a' as a constant in another scope.</span>
    <span class="SCmt">// Since 'a' is 1, the block will execute.</span>
    <span class="SLgc">if</span> <span class="SKwd">const</span> a = <span class="SNum">1</span> <span class="SLgc">do</span>
        <span class="SItr">@assert</span>(a == <span class="SNum">1</span>)
    <span class="SLgc">else</span> <span class="SLgc">do</span>
        <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    <span class="SLgc">if</span> <span class="SKwd">let</span> a = <span class="SNum">1</span> <span class="SLgc">do</span>
        <span class="SItr">@assert</span>(a == <span class="SNum">1</span>)
    <span class="SLgc">else</span> <span class="SLgc">do</span>
        <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
}

</span></div>
<h3 id="Adding_Conditions_with__where_">Adding Conditions with <span class="code-inline">where</span></h3>
<p>When an <span class="code-inline">if</span> statement includes a variable declaration, you can refine the test with a <span class="code-inline">where</span> clause. The <span class="code-inline">where</span> condition is only evaluated if the variable test passes.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">func</span> <span class="SFct">retSomething</span>()-&gt;<span class="STpe">string</span>     =&gt; <span class="SStr">"string"</span>
    <span class="SKwd">func</span> <span class="SFct">retNothing</span>()-&gt;<span class="SItr">#null</span> <span class="STpe">string</span> =&gt; <span class="SKwd">null</span>

    <span class="SCmt">// The 'where' clause runs only if 'str' is not null.</span>
    <span class="SLgc">if</span> <span class="SKwd">let</span> str = <span class="SFct">retSomething</span>() <span class="SLgc">where</span> str[<span class="SNum">0</span>] == '<span class="SFct">s</span>' <span class="SLgc">do</span>
        <span class="SItr">@assert</span>(<span class="SKwd">true</span>)
    <span class="SLgc">else</span> <span class="SLgc">do</span>
        <span class="SItr">@assert</span>(<span class="SKwd">false</span>)

    <span class="SCmt">// Since 'retNothing()' returns null, the 'where' clause is skipped.</span>
    <span class="SLgc">if</span> <span class="SKwd">let</span> str = <span class="SFct">retNothing</span>() <span class="SLgc">where</span> str[<span class="SNum">0</span>] == '<span class="SFct">s</span>' <span class="SLgc">do</span>
        <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    <span class="SLgc">else</span> <span class="SLgc">do</span>
        <span class="SItr">@assert</span>(<span class="SKwd">true</span>)
}

</span></div>
<h3 id="_005_002_for_swg">For</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="The__for__Loop">The <span class="code-inline">for</span> Loop</h3>
<p>The <span class="code-inline">for</span> construct in Swag enables iteration, allowing a block of code to execute repeatedly. This guide explores its features: basic usage, indexing, naming, reverse loops, early exits, range iteration, and advanced filtering using the <span class="code-inline">where</span> clause.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="Basic_Usage">Basic Usage</h3>
<p>The <span class="code-inline">for</span> expression specifies the number of iterations and is evaluated <b>once</b> before the loop starts. This expression must yield a <b>positive integer</b>.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> cpt = <span class="SNum">0</span>
    <span class="SLgc">for</span> <span class="SNum">10</span> <span class="SLgc">do</span>
        cpt += <span class="SNum">1</span>
    <span class="SItr">@assert</span>(cpt == <span class="SNum">10</span>)
}

</span></div>
<h3 id="Using___index_">Using <span class="code-inline">@index</span></h3>
<p>Within a <span class="code-inline">for</span>, the compiler provides the built-in <span class="code-inline">@index</span>, representing the current iteration (starting from 0).</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> cpt = <span class="SNum">0</span>'<span class="STpe">u64</span>
    <span class="SLgc">for</span> <span class="SNum">5</span>
    {
        cpt += <span class="SItr">@index</span>
    }

    <span class="SItr">@assert</span>(cpt == <span class="SNum">0</span> + <span class="SNum">1</span> + <span class="SNum">2</span> + <span class="SNum">3</span> + <span class="SNum">4</span>)
}

</span></div>
<h3 id="Naming_the_Loop_Index">Naming the Loop Index</h3>
<p>You can bind the loop index by putting its name in brackets. The brackets distinguish an index binding from an element binding, while <span class="code-inline">@index</span> remains accessible.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> cpt  = <span class="SNum">0</span>
    <span class="SKwd">var</span> cpt1 = <span class="SNum">0</span>

    <span class="SLgc">for</span> [i] <span class="SLgc">in</span> <span class="SNum">5</span>
    {
        cpt  += i
        cpt1 += <span class="SItr">@index</span>
    }

    <span class="SItr">@assert</span>(cpt == <span class="SNum">0</span> + <span class="SNum">1</span> + <span class="SNum">2</span> + <span class="SNum">3</span> + <span class="SNum">4</span>)
    <span class="SItr">@assert</span>(cpt1 == cpt)
}

</span></div>
<h3 id="Looping_Over_Arrays_and_Slices">Looping Over Arrays and Slices</h3>
<p>The <span class="code-inline">for</span> construct can iterate over any type supporting <span class="code-inline">@countof</span>, such as arrays, slices, or strings.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> arr = [<span class="SNum">10</span>, <span class="SNum">20</span>, <span class="SNum">30</span>, <span class="SNum">40</span>]
    <span class="SCmp">#assert</span>(<span class="SItr">@countof</span>(arr) == <span class="SNum">4</span>)

    <span class="SKwd">var</span> cpt = <span class="SNum">0</span>
    <span class="SLgc">for</span> arr <span class="SLgc">do</span>
        cpt += arr[<span class="SItr">@index</span>]
    <span class="SItr">@assert</span>(cpt == <span class="SNum">10</span> + <span class="SNum">20</span> + <span class="SNum">30</span> + <span class="SNum">40</span>)
}

</span></div>
<div class="blockquote blockquote-warning">
<div class="blockquote-title-block"><span class="blockquote-title">Warning</span></div>
<p>When iterating over strings, <span class="code-inline">for</span> loops over <b>bytes</b>, not runes. Use <span class="code-inline">Std.Core</span> for rune-based iteration.</p>
</div>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> cpt = <span class="SNum">0</span>
    <span class="SLgc">for</span> <span class="SStr">"â»"</span> <span class="SLgc">do</span>
        cpt += <span class="SNum">1</span>
    <span class="SItr">@assert</span>(cpt == <span class="SNum">3</span>)
}

</span></div>
<h3 id="Reverse_Looping">Reverse Looping</h3>
<p>To iterate in reverse order, add the <span class="code-inline">#reverse</span> modifier.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> cpt = <span class="SNum">0</span>

    <span class="SLgc">for</span> <span class="SItr">#reverse</span> <span class="SNum">3</span>
    {
        <span class="SLgc">if</span> cpt == <span class="SNum">0</span> <span class="SLgc">do</span>
            <span class="SItr">@assert</span>(<span class="SItr">@index</span> == <span class="SNum">2</span>)
        <span class="SLgc">elif</span> cpt == <span class="SNum">1</span> <span class="SLgc">do</span>
            <span class="SItr">@assert</span>(<span class="SItr">@index</span> == <span class="SNum">1</span>)
        <span class="SLgc">elif</span> cpt == <span class="SNum">2</span> <span class="SLgc">do</span>
            <span class="SItr">@assert</span>(<span class="SItr">@index</span> == <span class="SNum">0</span>)
        cpt += <span class="SNum">1</span>
    }
}

</span></div>
<h3 id="Using__break__and__continue_">Using <span class="code-inline">break</span> and <span class="code-inline">continue</span></h3>
<p>The <span class="code-inline">break</span> and <span class="code-inline">continue</span> keywords control loop flow. <span class="code-inline">break</span> exits the loop, while <span class="code-inline">continue</span> skips to the next iteration.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="Exiting_Early_with__break_">Exiting Early with <span class="code-inline">break</span></h3>
<p><span class="code-inline">break</span> stops the loop before completing all iterations.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> cpt = <span class="SNum">0</span>
    <span class="SLgc">for</span> [x] <span class="SLgc">in</span> <span class="SNum">10</span>
    {
        <span class="SLgc">if</span> x == <span class="SNum">5</span> <span class="SLgc">do</span>
            <span class="SLgc">break</span>
        cpt += <span class="SNum">1</span>
    }

    <span class="SItr">@assert</span>(cpt == <span class="SNum">5</span>)
}

</span></div>
<h3 id="Skipping_Iterations_with__continue_">Skipping Iterations with <span class="code-inline">continue</span></h3>
<p><span class="code-inline">continue</span> skips the current iteration and proceeds to the next.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> cpt = <span class="SNum">0</span>
    <span class="SLgc">for</span> [x] <span class="SLgc">in</span> <span class="SNum">10</span>
    {
        <span class="SLgc">if</span> x == <span class="SNum">5</span> <span class="SLgc">do</span>
            <span class="SLgc">continue</span>
        cpt += <span class="SNum">1</span>
    }

    <span class="SItr">@assert</span>(cpt == <span class="SNum">9</span>)
}

</span></div>
<h3 id="Ranges">Ranges</h3>
<p>The <span class="code-inline">for</span> loop supports signed integer ranges, offering flexible intervals.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="Looping_Over_a_Range_with__to_">Looping Over a Range with <span class="code-inline">to</span></h3>
<p><span class="code-inline">to</span> defines an inclusive range loop.</p>
<div class="blockquote blockquote-note">
<div class="blockquote-title-block"><span class="blockquote-title">Note</span></div>
<p>An inverted range, whose start is above its end, selects nothing and the loop runs zero times. A loop asks whether the index is still within the range, and an inverted range answers no immediately, so this holds in every build configuration. Writing constant inverted bounds is still a compile-time error, because there the inversion is a certainty rather than an empty interval that happened to come out of a computation.</p>
</div>
<div class="blockquote blockquote-warning">
<div class="blockquote-title-block"><span class="blockquote-title">Warning</span></div>
<p>On an <b>unsigned</b> counter, do not write a collection-sized loop as <span class="code-inline">for [i] in 0 to count - 1</span>. This has nothing to do with inverted ranges: when <span class="code-inline">count</span> is zero, <span class="code-inline">count - 1</span> wraps to the largest value of the type, and the resulting range is valid and ascending, so no range rule can catch it. Only the overflow guard reports it, and it is off in <span class="code-inline">release</span>. Write <span class="code-inline">for [i] in 0 until count</span>, which needs no subtraction and is empty for a zero count.</p>
</div>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> count = <span class="SNum">0</span>
    <span class="SKwd">var</span> sum   = <span class="SNum">0</span>

    <span class="SLgc">for</span> [i] <span class="SLgc">in</span> -<span class="SNum">1</span> <span class="SLgc">to</span> <span class="SNum">1</span>
    {
        count += <span class="SNum">1</span>
        sum   += i
    }

    <span class="SItr">@assert</span>(sum == <span class="SNum">0</span>)
    <span class="SItr">@assert</span>(count == <span class="SNum">3</span>)
}

</span></div>
<h3 id="Excluding_the_Last_Value_with__until_">Excluding the Last Value with <span class="code-inline">until</span></h3>
<p><span class="code-inline">until</span> defines a range that excludes the end value.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> cpt = <span class="SNum">0</span>
    <span class="SLgc">for</span> [i] <span class="SLgc">in</span> <span class="SNum">1</span> <span class="SLgc">until</span> <span class="SNum">3</span>
    {
        cpt += i
    }

    <span class="SItr">@assert</span>(cpt == <span class="SNum">1</span> + <span class="SNum">2</span>)
}

</span></div>
<h3 id="Empty_Ranges">Empty Ranges</h3>
<p>An <span class="code-inline">until</span> range whose bounds are equal is <b>empty</b>: the loop runs zero times. This makes <span class="code-inline">for [i] in 0 until count</span> safe when <span class="code-inline">count</span> is zero, so a collection-sized loop needs no guard of its own. Only an inverted range, where the lower bound is above the upper bound, is an error.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">func</span> <span class="SFct">sumUpTo</span>(count: <span class="STpe">s32</span>)-&gt;<span class="STpe">s32</span>
    {
        <span class="SKwd">var</span> sum = <span class="SNum">0</span>
        <span class="SLgc">for</span> [i] <span class="SLgc">in</span> <span class="SNum">0</span> <span class="SLgc">until</span> count <span class="SLgc">do</span>
            sum += i
        <span class="SLgc">return</span> sum
    }

    <span class="SItr">@assert</span>(<span class="SFct">sumUpTo</span>(<span class="SNum">0</span>) == <span class="SNum">0</span>)
    <span class="SItr">@assert</span>(<span class="SFct">sumUpTo</span>(<span class="SNum">4</span>) == <span class="SNum">0</span> + <span class="SNum">1</span> + <span class="SNum">2</span> + <span class="SNum">3</span>)

    <span class="SCmt">// The same holds for a constant empty range, and away from zero.</span>
    <span class="SKwd">var</span> cpt = <span class="SNum">0</span>
    <span class="SLgc">for</span> [i] <span class="SLgc">in</span> <span class="SNum">7</span> <span class="SLgc">until</span> <span class="SNum">7</span> <span class="SLgc">do</span>
        cpt += <span class="SNum">1</span>
    <span class="SItr">@assert</span>(cpt == <span class="SNum">0</span>)
}

</span></div>
<h3 id="Reverse_Range_Looping">Reverse Range Looping</h3>
<p>Use <span class="code-inline">#reverse</span> to iterate a range in reverse order.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SLgc">for</span> <span class="SItr">#reverse</span> <span class="SNum">0</span> <span class="SLgc">to</span> <span class="SNum">5</span> {}

    <span class="SLgc">for</span> <span class="SItr">#reverse</span> -<span class="SNum">1</span> <span class="SLgc">to</span> <span class="SNum">1</span> {}

    <span class="SLgc">for</span> <span class="SItr">#reverse</span> -<span class="SNum">2</span> <span class="SLgc">until</span> <span class="SNum">2</span> {}
}

</span></div>
<h3 id="Infinite_Loop">Infinite Loop</h3>
<p>A <span class="code-inline">for</span> without an expression creates an infinite loop, similar to <span class="code-inline">while true {}</span>. Use <span class="code-inline">break</span> to exit.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SLgc">for</span>
    {
        <span class="SLgc">if</span> <span class="SItr">@index</span> == <span class="SNum">4</span> <span class="SLgc">do</span>
            <span class="SLgc">break</span>
    }
}

</span></div>
<h3 id="Using__where__Clause">Using <span class="code-inline">where</span> Clause</h3>
<p>The <span class="code-inline">where</span> clause filters iterations based on conditions.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="Basic__where__Clause">Basic <span class="code-inline">where</span> Clause</h3>
<p>Attach <span class="code-inline">where</span> to apply a filter to the loop index or element. Only iterations meeting the condition are executed.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> result = <span class="SNum">0</span>

    <span class="SLgc">for</span> [i] <span class="SLgc">in</span> <span class="SNum">10</span> <span class="SLgc">where</span> i % <span class="SNum">2</span> == <span class="SNum">0</span>
    {
        result += i
    }

    <span class="SItr">@assert</span>(result == <span class="SNum">0</span> + <span class="SNum">2</span> + <span class="SNum">4</span> + <span class="SNum">6</span> + <span class="SNum">8</span>)
}

</span></div>
<h3 id="Filtering_Arrays_with__where_">Filtering Arrays with <span class="code-inline">where</span></h3>
<p>Loop over the element count and use <span class="code-inline">where</span> to filter which indices run the body.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> arr        = [<span class="SNum">10</span>, <span class="SNum">21</span>, <span class="SNum">30</span>, <span class="SNum">41</span>, <span class="SNum">50</span>]
    <span class="SKwd">var</span> sumOfEvens = <span class="SNum">0</span>

    <span class="SLgc">for</span> [i] <span class="SLgc">in</span> <span class="SItr">@countof</span>(arr) <span class="SLgc">where</span> arr[i] % <span class="SNum">2</span> == <span class="SNum">0</span>
    {
        sumOfEvens += arr[i]
    }

    <span class="SItr">@assert</span>(sumOfEvens == <span class="SNum">10</span> + <span class="SNum">30</span> + <span class="SNum">50</span>)
}

</span></div>
<h3 id="Complex_Conditions_with__where_">Complex Conditions with <span class="code-inline">where</span></h3>
<p>The <span class="code-inline">where</span> clause supports multiple logical conditions for advanced filtering.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> arr         = [<span class="SNum">10</span>, <span class="SNum">15</span>, <span class="SNum">20</span>, <span class="SNum">25</span>, <span class="SNum">30</span>, <span class="SNum">35</span>]
    <span class="SKwd">var</span> filteredSum = <span class="SNum">0</span>

    <span class="SLgc">for</span> [i] <span class="SLgc">in</span> <span class="SItr">@countof</span>(arr) <span class="SLgc">where</span> arr[i] % <span class="SNum">2</span> == <span class="SNum">0</span> <span class="SLgc">and</span> arr[i] &gt; <span class="SNum">15</span>
    {
        filteredSum += arr[i]
    }

    <span class="SItr">@assert</span>(filteredSum == <span class="SNum">20</span> + <span class="SNum">30</span>)
}

<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> arr        = [<span class="SNum">10</span>, <span class="SNum">25</span>, <span class="SNum">30</span>, <span class="SNum">45</span>, <span class="SNum">50</span>, <span class="SNum">65</span>]
    <span class="SKwd">var</span> complexSum = <span class="SNum">0</span>

    <span class="SLgc">for</span> [i] <span class="SLgc">in</span> <span class="SItr">@countof</span>(arr) <span class="SLgc">where</span> arr[i] % <span class="SNum">2</span> == <span class="SNum">0</span> <span class="SLgc">or</span> arr[i] &gt; <span class="SNum">40</span>
    {
        complexSum += arr[i]
    }

    <span class="SItr">@assert</span>(complexSum == <span class="SNum">10</span> + <span class="SNum">30</span> + <span class="SNum">45</span> + <span class="SNum">50</span> + <span class="SNum">65</span>)
}

</span></div>
<h3 id="Filtering_Ranges_with__where_">Filtering Ranges with <span class="code-inline">where</span></h3>
<p>The <span class="code-inline">where</span> clause can also be applied to ranges.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> sumOfPositiveEvens = <span class="SNum">0</span>

    <span class="SLgc">for</span> [i] <span class="SLgc">in</span> -<span class="SNum">5</span> <span class="SLgc">to</span> <span class="SNum">5</span> <span class="SLgc">where</span> i &gt; <span class="SNum">0</span> <span class="SLgc">and</span> i % <span class="SNum">2</span> == <span class="SNum">0</span>
    {
        sumOfPositiveEvens += i
    }

    <span class="SItr">@assert</span>(sumOfPositiveEvens == <span class="SNum">2</span> + <span class="SNum">4</span>)
}

</span></div>
<h3 id="Combining___reverse__and__where_">Combining <span class="code-inline">#reverse</span> and <span class="code-inline">where</span></h3>
<p>You can combine <span class="code-inline">#reverse</span> with <span class="code-inline">where</span> for reverse conditional iteration.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> arr         = [<span class="SNum">10</span>, <span class="SNum">20</span>, <span class="SNum">30</span>, <span class="SNum">40</span>, <span class="SNum">50</span>]
    <span class="SKwd">var</span> reversedSum = <span class="SNum">0</span>

    <span class="SLgc">for</span> <span class="SItr">#reverse</span> [i] <span class="SLgc">in</span> <span class="SItr">@countof</span>(arr) <span class="SLgc">where</span> arr[i] % <span class="SNum">2</span> == <span class="SNum">0</span>
    {
        reversedSum += arr[i]
    }

    <span class="SItr">@assert</span>(reversedSum == <span class="SNum">50</span> + <span class="SNum">40</span> + <span class="SNum">30</span> + <span class="SNum">20</span> + <span class="SNum">10</span>)
}

</span></div>
<h3 id="C-like__for_">C-like <span class="code-inline">for</span></h3>
<p>Swag also supports a C-style <span class="code-inline">for</span> loop with initialization, condition, and increment sections.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> cpt = <span class="SNum">0</span>

    <span class="SCmt">// Standard syntax</span>
    <span class="SLgc">for</span> <span class="SKwd">var</span> i = <span class="SNum">0</span>; i &lt; <span class="SNum">10</span>; i += <span class="SNum">1</span> <span class="SLgc">do</span>
        cpt += <span class="SNum">1</span>
    <span class="SItr">@assert</span>(cpt == <span class="SNum">10</span>)

    <span class="SCmt">// Alternative syntax with newlines</span>
    <span class="SLgc">for</span> <span class="SKwd">var</span> i = <span class="SNum">0</span>; i &lt; <span class="SNum">10</span>; i += <span class="SNum">1</span>
    {
        cpt += <span class="SNum">1</span>
    }

    <span class="SItr">@assert</span>(cpt == <span class="SNum">20</span>)
}

</span></div>
<h3 id="Accessing_Loop_Index_with___index_">Accessing Loop Index with <span class="code-inline">@index</span></h3>
<p>In all <span class="code-inline">for</span> variants, <span class="code-inline">@index</span> provides the current iteration index.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> cpt = <span class="SNum">0</span>'<span class="STpe">u64</span>

    <span class="SLgc">for</span> <span class="SKwd">var</span> i: <span class="STpe">u32</span> = <span class="SNum">10</span>; i &lt; <span class="SNum">15</span>; i += <span class="SNum">1</span> <span class="SLgc">do</span>
        cpt += <span class="SItr">@index</span>
    <span class="SItr">@assert</span>(cpt == <span class="SNum">0</span> + <span class="SNum">1</span> + <span class="SNum">2</span> + <span class="SNum">3</span> + <span class="SNum">4</span>)

    <span class="SKwd">var</span> cpt1 = <span class="SNum">0</span>'<span class="STpe">u64</span>
    <span class="SLgc">for</span> <span class="SKwd">var</span> i = <span class="SNum">10</span>; i &lt; <span class="SNum">15</span>; i += <span class="SNum">1</span> <span class="SLgc">do</span>
        cpt1 += <span class="SItr">@index</span>
    <span class="SItr">@assert</span>(cpt1 == <span class="SNum">0</span> + <span class="SNum">1</span> + <span class="SNum">2</span> + <span class="SNum">3</span> + <span class="SNum">4</span>)
}

</span></div>
<h3 id="Using__break__and__continue__in__for__Loops">Using <span class="code-inline">break</span> and <span class="code-inline">continue</span> in <span class="code-inline">for</span> Loops</h3>
<p><span class="code-inline">break</span> exits the loop early, and <span class="code-inline">continue</span> skips to the next iteration.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> sum = <span class="SNum">0</span>

    <span class="SLgc">for</span> <span class="SKwd">var</span> i = <span class="SNum">0</span>; i &lt; <span class="SNum">10</span>; i += <span class="SNum">1</span>
    {
        <span class="SLgc">if</span> i == <span class="SNum">5</span> <span class="SLgc">do</span>
            <span class="SLgc">break</span>
        sum += i
    }

    <span class="SItr">@assert</span>(sum == <span class="SNum">0</span> + <span class="SNum">1</span> + <span class="SNum">2</span> + <span class="SNum">3</span> + <span class="SNum">4</span>)

    sum = <span class="SNum">0</span>
    <span class="SLgc">for</span> <span class="SKwd">var</span> i = <span class="SNum">0</span>; i &lt; <span class="SNum">10</span>; i += <span class="SNum">1</span>
    {
        <span class="SLgc">if</span> i % <span class="SNum">2</span> == <span class="SNum">0</span> <span class="SLgc">do</span>
            <span class="SLgc">continue</span>
        sum += i
    }

    <span class="SItr">@assert</span>(sum == <span class="SNum">1</span> + <span class="SNum">3</span> + <span class="SNum">5</span> + <span class="SNum">7</span> + <span class="SNum">9</span>)
}

</span></div>
<h3 id="Nested__for__Loops">Nested <span class="code-inline">for</span> Loops</h3>
<p>Swag supports nested loops. In nested contexts, <span class="code-inline">@index</span> refers to the current innermost loop.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> result = <span class="SNum">0</span>'<span class="STpe">u64</span>

    <span class="SLgc">for</span> <span class="SKwd">var</span> i = <span class="SNum">0</span>; i &lt; <span class="SNum">5</span>; i += <span class="SNum">1</span>
    {
        <span class="SLgc">for</span> <span class="SKwd">var</span> j = <span class="SNum">0</span>; j &lt; <span class="SNum">5</span>; j += <span class="SNum">1</span>
        {
            result += <span class="SItr">@index</span>
        }
    }

    <span class="SItr">@assert</span>(result == <span class="SNum">10</span> * <span class="SNum">5</span>)
}

</span></div>
<h3 id="Iterating_Over_Arrays_with__for_">Iterating Over Arrays with <span class="code-inline">for</span></h3>
<p>You can also use <span class="code-inline">for</span> to iterate over arrays and collections.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> array = [<span class="SNum">1</span>, <span class="SNum">2</span>, <span class="SNum">3</span>, <span class="SNum">4</span>, <span class="SNum">5</span>]
    <span class="SKwd">var</span> sum   = <span class="SNum">0</span>

    <span class="SLgc">for</span> <span class="SKwd">var</span> i = <span class="SNum">0</span>; i &lt; <span class="SItr">@countof</span>(array); i += <span class="SNum">1</span>
    {
        sum += array[i]
    }

    <span class="SItr">@assert</span>(sum == <span class="SNum">1</span> + <span class="SNum">2</span> + <span class="SNum">3</span> + <span class="SNum">4</span> + <span class="SNum">5</span>)
}

</span></div>
<h3 id="_005_003_for_elements_swg">For Elements</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Element_Iteration_with__for_">Element Iteration with <span class="code-inline">for</span></h3>
<p>Binding a name in a <span class="code-inline">for</span> statement iterates over all elements of a collection (arrays, slices, strings, and even structs), providing a streamlined and efficient way to process each item.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SLgc">for</span> value <span class="SLgc">in</span> <span class="SStr">"ABC"</span>
    {
        <span class="SKwd">let</span> a = <span class="SItr">@index</span>
        <span class="SLgc">switch</span> a
        {
        <span class="SLgc">case</span> <span class="SNum">0</span>: <span class="SItr">@assert</span>(value == '<span class="SFct">A</span>')
        <span class="SLgc">case</span> <span class="SNum">1</span>: <span class="SItr">@assert</span>(value == '<span class="SFct">B</span>')
        <span class="SLgc">case</span> <span class="SNum">2</span>: <span class="SItr">@assert</span>(value == '<span class="SFct">C</span>')
        }
    }
}

</span></div>
<h3 id="Naming_Only_the_Index">Naming Only the Index</h3>
<p>Put a name in brackets to bind the index without binding the element. The same form is used for counted loops: <span class="code-inline">for [index] in 3</span>.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> sum = <span class="SNum">0</span>'<span class="STpe">u64</span>

    <span class="SLgc">for</span> [index] <span class="SLgc">in</span> <span class="SStr">"ABC"</span>
    {
        <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(index) == <span class="STpe">u64</span>)
        sum += index
    }

    <span class="SItr">@assert</span>(sum == <span class="SNum">3</span>)
}

</span></div>
<h3 id="Naming_the_Value_and_Index">Naming the Value and Index</h3>
<p>You can explicitly name both the element <span class="code-inline">value</span> and the loop <span class="code-inline">index</span> to improve readability, especially in nested loops or with complex data structures. The value is written normally, and the index is written in brackets.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SLgc">for</span> value, [index] <span class="SLgc">in</span> <span class="SStr">"ABC"</span>
    {
        <span class="SKwd">let</span> a = index
        <span class="SLgc">switch</span> a
        {
        <span class="SLgc">case</span> <span class="SNum">0</span>: <span class="SItr">@assert</span>(value == '<span class="SFct">A</span>')
        <span class="SLgc">case</span> <span class="SNum">1</span>: <span class="SItr">@assert</span>(value == '<span class="SFct">B</span>')
        <span class="SLgc">case</span> <span class="SNum">2</span>: <span class="SItr">@assert</span>(value == '<span class="SFct">C</span>')
        }
    }
}

</span></div>
<h3 id="Enum-Indexed_Arrays">Enum-Indexed Arrays</h3>
<p>When an array dimension is an enum, its index binding has that enum type. This keeps iteration and indexing type-safe without converting through an integer.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">enum</span> <span class="SCst">Channel</span>: <span class="STpe">u8</span>
{
    <span class="SCst">Blue</span>  = <span class="SNum">2</span>
    <span class="SCst">Red</span>   = <span class="SNum">0</span>
    <span class="SCst">Green</span> = <span class="SNum">1</span>
}

<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> levels: [<span class="SCst">Channel</span>] <span class="STpe">s32</span> = [<span class="SNum">10</span>, <span class="SNum">20</span>, <span class="SNum">30</span>]
    <span class="SKwd">var</span> sum                   = <span class="SNum">0</span>

    <span class="SLgc">for</span> value, [channel] <span class="SLgc">in</span> levels
    {
        <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(channel) == <span class="SCst">Channel</span>)
        <span class="SItr">@assert</span>(value == levels[channel])
        sum += value
    }

    <span class="SItr">@assert</span>(sum == <span class="SNum">60</span>)
}

</span></div>
<h3 id="Reverse_Order_with___reverse_">Reverse Order with <span class="code-inline">#reverse</span></h3>
<p>Iterate from the last element to the first by adding the <span class="code-inline">#reverse</span> modifier. <span class="code-inline">@index</span> still reflects the loop index within the original collection.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> cpt = <span class="SNum">0</span>
    <span class="SLgc">for</span> <span class="SItr">#reverse</span> value <span class="SLgc">in</span> <span class="SStr">"ABC"</span>
    {
        <span class="SLgc">switch</span> cpt
        {
        <span class="SLgc">case</span> <span class="SNum">0</span>:
            <span class="SItr">@assert</span>(value == '<span class="SFct">C</span>')
            <span class="SItr">@assert</span>(<span class="SItr">@index</span> == <span class="SNum">2</span>)

        <span class="SLgc">case</span> <span class="SNum">1</span>:
            <span class="SItr">@assert</span>(value == '<span class="SFct">B</span>')
            <span class="SItr">@assert</span>(<span class="SItr">@index</span> == <span class="SNum">1</span>)

        <span class="SLgc">case</span> <span class="SNum">2</span>:
            <span class="SItr">@assert</span>(value == '<span class="SFct">A</span>')
            <span class="SItr">@assert</span>(<span class="SItr">@index</span> == <span class="SNum">0</span>)
        }

        cpt += <span class="SNum">1</span>
    }
}

</span></div>
<h3 id="Visiting_Arrays_and_Slices">Visiting Arrays and Slices</h3>
<p>Use <span class="code-inline">for</span> with a binding to traverse arrays or slices and process each element.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> array  = [<span class="SNum">10</span>, <span class="SNum">20</span>, <span class="SNum">30</span>]
    <span class="SKwd">var</span> result = <span class="SNum">0</span>
    <span class="SLgc">for</span> it <span class="SLgc">in</span> array <span class="SLgc">do</span>
        result += it
    <span class="SItr">@assert</span>(result == <span class="SNum">10</span> + <span class="SNum">20</span> + <span class="SNum">30</span>)
}

</span></div>
<h3 id="Multi-dimensional_Arrays">Multi-dimensional Arrays</h3>
<p>Element iteration works with multi-dimensional arrays and visits each element in row-major order.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> array: [<span class="SNum">2</span>, <span class="SNum">2</span>] <span class="STpe">s32</span> = [[<span class="SNum">10</span>, <span class="SNum">20</span>], [<span class="SNum">30</span>, <span class="SNum">40</span>]]
    <span class="SKwd">var</span> result            = <span class="SNum">0</span>
    <span class="SLgc">for</span> it <span class="SLgc">in</span> array <span class="SLgc">do</span>
        result += it
    <span class="SItr">@assert</span>(result == <span class="SNum">10</span> + <span class="SNum">20</span> + <span class="SNum">30</span> + <span class="SNum">40</span>)
}

</span></div>
<h3 id="Modifying_Elements_with____">Modifying Elements with <span class="code-inline">&amp;</span></h3>
<p>Prefix the element name with <span class="code-inline">&amp;</span> to visit elements by address and modify them in place.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> array: [<span class="SNum">2</span>, <span class="SNum">2</span>] <span class="STpe">s32</span> = [[<span class="SNum">1</span>, <span class="SNum">2</span>], [<span class="SNum">3</span>, <span class="SNum">4</span>]]
    <span class="SKwd">var</span> result            = <span class="SNum">0</span>

    <span class="SLgc">for</span> &amp;it <span class="SLgc">in</span> array
    {
        result += it
        it     = <span class="SNum">555</span>
    }

    <span class="SItr">@assert</span>(result == <span class="SNum">1</span> + <span class="SNum">2</span> + <span class="SNum">3</span> + <span class="SNum">4</span>)
    <span class="SItr">@assert</span>(array[<span class="SNum">0</span>, <span class="SNum">0</span>] == <span class="SNum">555</span>)
    <span class="SItr">@assert</span>(array[<span class="SNum">0</span>, <span class="SNum">1</span>] == <span class="SNum">555</span>)
    <span class="SItr">@assert</span>(array[<span class="SNum">1</span>, <span class="SNum">0</span>] == <span class="SNum">555</span>)
    <span class="SItr">@assert</span>(array[<span class="SNum">1</span>, <span class="SNum">1</span>] == <span class="SNum">555</span>)
}

</span></div>
<h3 id="Filtering_with__where_">Filtering with <span class="code-inline">where</span></h3>
<p>Add a <span class="code-inline">where</span> clause to process only elements that satisfy a condition. This avoids explicit branching inside the loop.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> array: [?] <span class="STpe">s32</span> = [<span class="SNum">1</span>, <span class="SNum">2</span>, <span class="SNum">3</span>, <span class="SNum">4</span>]
    <span class="SKwd">var</span> result         = <span class="SNum">0</span>

    <span class="SLgc">for</span> value <span class="SLgc">in</span> array <span class="SLgc">where</span> value &amp; <span class="SNum">1</span> == <span class="SNum">0</span> <span class="SLgc">do</span>
        result += value
    <span class="SItr">@assert</span>(result == <span class="SNum">6</span>)

    <span class="SCmt">// Equivalent with an 'if' guard:</span>
    result = <span class="SNum">0</span>
    <span class="SLgc">for</span> value <span class="SLgc">in</span> array <span class="SLgc">do</span>
        <span class="SLgc">if</span> value &amp; <span class="SNum">1</span> == <span class="SNum">0</span> <span class="SLgc">do</span>
            result += value
    <span class="SItr">@assert</span>(result == <span class="SNum">6</span>)

    <span class="SCmt">// Equivalent using 'continue' to skip odd values:</span>
    result = <span class="SNum">0</span>
    <span class="SLgc">for</span> value <span class="SLgc">in</span> array
    {
        <span class="SLgc">if</span> (value &amp; <span class="SNum">1</span>) != <span class="SNum">0</span> <span class="SLgc">do</span>
            <span class="SLgc">continue</span>
        result += value
    }

    <span class="SItr">@assert</span>(result == <span class="SNum">6</span>)
}

</span></div>
<h3 id="_005_004_while_swg">While</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="The__while__Loop">The <span class="code-inline">while</span> Loop</h3>
<p>A <span class="code-inline">while</span> loop repeatedly executes a block of code as long as its condition evaluates to <span class="code-inline">true</span>. Once the condition becomes <span class="code-inline">false</span>, the loop terminates.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> i = <span class="SNum">0</span>
    <span class="SLgc">while</span> i &lt; <span class="SNum">10</span> <span class="SLgc">do</span>
        i += <span class="SNum">1</span>
    <span class="SItr">@assert</span>(i == <span class="SNum">10</span>)
}

</span></div>
<h3 id="Breaking_Out_of_a__while__Loop">Breaking Out of a <span class="code-inline">while</span> Loop</h3>
<p>The <span class="code-inline">break</span> statement allows an early exit from a <span class="code-inline">while</span> loop before the condition becomes <span class="code-inline">false</span>. This is useful when you need to stop the loop based on a specific condition.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> i = <span class="SNum">0</span>
    <span class="SLgc">while</span> i &lt; <span class="SNum">10</span>
    {
        <span class="SLgc">if</span> i == <span class="SNum">5</span> <span class="SLgc">do</span>
            <span class="SLgc">break</span>
        i += <span class="SNum">1</span>
    }

    <span class="SItr">@assert</span>(i == <span class="SNum">5</span>)
}

</span></div>
<h3 id="Skipping_Iterations_with__continue_">Skipping Iterations with <span class="code-inline">continue</span></h3>
<p>The <span class="code-inline">continue</span> statement skips the current iteration and jumps to the next one. It is useful for ignoring specific cases within the loop.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> sum = <span class="SNum">0</span>
    <span class="SKwd">var</span> i   = <span class="SNum">0</span>

    <span class="SLgc">while</span> i &lt; <span class="SNum">10</span>
    {
        i += <span class="SNum">1</span>
        <span class="SLgc">if</span> i % <span class="SNum">2</span> == <span class="SNum">0</span> <span class="SLgc">do</span>
            <span class="SLgc">continue</span>
        sum += i
    }

    <span class="SItr">@assert</span>(sum == <span class="SNum">25</span>)
}

</span></div>
<h3 id="Nested__while__Loops">Nested <span class="code-inline">while</span> Loops</h3>
<p>A <span class="code-inline">while</span> loop can contain another <span class="code-inline">while</span> loop. <span class="code-inline">break</span> and <span class="code-inline">continue</span> only affect the loop in which they are directly used.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> i     = <span class="SNum">0</span>
    <span class="SKwd">var</span> j     = <span class="SNum">0</span>
    <span class="SKwd">var</span> count = <span class="SNum">0</span>

    <span class="SLgc">while</span> i &lt; <span class="SNum">3</span>
    {
        j = <span class="SNum">0</span>
        <span class="SLgc">while</span> j &lt; <span class="SNum">3</span>
        {
            <span class="SLgc">if</span> j == <span class="SNum">2</span> <span class="SLgc">do</span>
                <span class="SLgc">break</span>
            count += <span class="SNum">1</span>
            j     += <span class="SNum">1</span>
        }

        i += <span class="SNum">1</span>
    }

    <span class="SItr">@assert</span>(count == <span class="SNum">6</span>)
}

</span></div>
<h3 id="Using__while__with_Complex_Conditions">Using <span class="code-inline">while</span> with Complex Conditions</h3>
<p>The condition in a <span class="code-inline">while</span> loop can include logical operators such as <span class="code-inline">and</span> and <span class="code-inline">or</span> for more complex and controlled iteration logic.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> a          = <span class="SNum">0</span>
    <span class="SKwd">var</span> b          = <span class="SNum">1</span>
    <span class="SKwd">var</span> iterations = <span class="SNum">0</span>

    <span class="SLgc">while</span> a &lt; <span class="SNum">100</span> <span class="SLgc">and</span> b &lt; <span class="SNum">200</span>
    {
        a          += <span class="SNum">10</span>
        b          += <span class="SNum">20</span>
        iterations += <span class="SNum">1</span>
    }

    <span class="SItr">@assert</span>(a == <span class="SNum">100</span>)
    <span class="SItr">@assert</span>(b == <span class="SNum">201</span>)
    <span class="SItr">@assert</span>(iterations == <span class="SNum">10</span>)
}

</span></div>
<h3 id="_005_005_switch_swg">Switch</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="The__switch__Statement">The <span class="code-inline">switch</span> Statement</h3>
<p>The <span class="code-inline">switch</span> statement in Swag behaves similarly to C/C++, with one key difference: Swag <b>does not require `break`</b> at the end of each case. Unintentional fallthroughs are prevented by default, ensuring each <span class="code-inline">case</span> is isolated unless explicitly linked with <span class="code-inline">fallthrough</span>.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> value = <span class="SNum">6</span>

    <span class="SLgc">switch</span> value
    {
    <span class="SLgc">case</span> <span class="SNum">0</span>:  <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    <span class="SLgc">case</span> <span class="SNum">5</span>:  <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    <span class="SLgc">case</span> <span class="SNum">6</span>:  <span class="SItr">@assert</span>(<span class="SKwd">true</span>)
    <span class="SLgc">default</span>: <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    }

    <span class="SKwd">let</span> ch = '<span class="SFct">A</span>'<span class="STpe">rune</span>

    <span class="SLgc">switch</span> ch
    {
    <span class="SLgc">case</span> '<span class="SFct">B</span>': <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    <span class="SLgc">case</span> '<span class="SFct">A</span>': <span class="SLgc">break</span>
    }
}

</span></div>
<h3 id="Multiple_Values_in_a__case_">Multiple Values in a <span class="code-inline">case</span></h3>
<p>A <span class="code-inline">case</span> can match multiple values, simplifying logic when several values share the same behavior.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> value = <span class="SNum">6</span>

    <span class="SLgc">switch</span> value
    {
    <span class="SLgc">case</span> <span class="SNum">2</span>, <span class="SNum">4</span>, <span class="SNum">6</span>: <span class="SItr">@assert</span>(<span class="SKwd">true</span>)
    <span class="SLgc">default</span>:      <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    }

    <span class="SCmt">// Alternatively, list each value on its own line for clarity.</span>
    <span class="SLgc">switch</span> value
    {
    <span class="SLgc">case</span> <span class="SNum">2</span>,
         <span class="SNum">4</span>,
         <span class="SNum">6</span>: <span class="SItr">@assert</span>(<span class="SKwd">true</span>)

    <span class="SLgc">default</span>: <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    }
}

</span></div>
<h3 id="Using__switch__with_Various_Types">Using <span class="code-inline">switch</span> with Various Types</h3>
<p><span class="code-inline">switch</span> supports any type that implements <span class="code-inline">==</span>, including strings and user-defined comparable types.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> value = <span class="SStr">"myString"</span>

    <span class="SLgc">switch</span> value
    {
    <span class="SLgc">case</span> <span class="SStr">"myString"</span>:    <span class="SItr">@assert</span>(<span class="SKwd">true</span>)
    <span class="SLgc">case</span> <span class="SStr">"otherString"</span>: <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    <span class="SLgc">default</span>:            <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    }
}

</span></div>
<h3 id="Intentional_Fallthrough_with__fallthrough_">Intentional Fallthrough with <span class="code-inline">fallthrough</span></h3>
<p>Use <span class="code-inline">fallthrough</span> to intentionally continue execution into the next case.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> value = <span class="SNum">6</span>

    <span class="SLgc">switch</span> value
    {
    <span class="SLgc">case</span> <span class="SNum">6</span>:  <span class="SLgc">fallthrough</span>
    <span class="SLgc">case</span> <span class="SNum">7</span>:  <span class="SItr">@assert</span>(value == <span class="SNum">6</span>)
    <span class="SLgc">default</span>: <span class="SItr">@assert</span>(<span class="SKwd">true</span>)
    }
}

</span></div>
<h3 id="Exiting_a__case__Early_with__break_">Exiting a <span class="code-inline">case</span> Early with <span class="code-inline">break</span></h3>
<p>Use <span class="code-inline">break</span> to exit a <span class="code-inline">case</span> early when a certain condition is met.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> value = <span class="SNum">6</span>

    <span class="SLgc">switch</span> value
    {
    <span class="SLgc">case</span> <span class="SNum">6</span>:
        <span class="SLgc">if</span> value == <span class="SNum">6</span> <span class="SLgc">do</span>
            <span class="SLgc">break</span>
        <span class="SItr">@assert</span>(<span class="SKwd">false</span>)

    <span class="SLgc">default</span>:
        <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    }
}

</span></div>
<h3 id="Handling_Empty_Cases_with__break_">Handling Empty Cases with <span class="code-inline">break</span></h3>
<p>A <span class="code-inline">case</span> cannot be left empty. Use <span class="code-inline">break</span> explicitly when no action is required.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> value = <span class="SNum">6</span>

    <span class="SLgc">switch</span> value
    {
    <span class="SLgc">case</span> <span class="SNum">5</span>:  <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    <span class="SLgc">case</span> <span class="SNum">6</span>:  <span class="SLgc">break</span>
    <span class="SLgc">default</span>: <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    }
}

</span></div>
<h3 id="Variable_and_Expression_Cases">Variable and Expression Cases</h3>
<p><span class="code-inline">switch</span> cases can use variables and expressions, evaluated dynamically at runtime.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> test = <span class="SNum">2</span>
    <span class="SKwd">let</span> a    = <span class="SNum">0</span>
    <span class="SKwd">let</span> b    = <span class="SNum">1</span>

    <span class="SLgc">switch</span> test
    {
    <span class="SLgc">case</span> a:     <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    <span class="SLgc">case</span> b:     <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    <span class="SLgc">case</span> b + <span class="SNum">1</span>: <span class="SItr">@assert</span>(<span class="SKwd">true</span>)
    }
}

</span></div>
<h3 id="Enum_Case_Values">Enum Case Values</h3>
<p>When the switch expression is an enum, write inferred enum values with a leading dot, such as <span class="code-inline">case .Ready</span>. The bare form <span class="code-inline">case Ready</span> is not auto-scoped. Ordinary constants and other case expressions remain valid.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">enum</span> <span class="SCst">State</span> { <span class="SCst">Idle</span>, <span class="SCst">Ready</span> }
    <span class="SKwd">let</span> state = <span class="SCst">State</span>.<span class="SCst">Ready</span>

    <span class="SLgc">switch</span> state
    {
    <span class="SLgc">case</span> .<span class="SCst">Idle</span>:  <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    <span class="SLgc">case</span> .<span class="SCst">Ready</span>: <span class="SLgc">break</span>
    }
}

</span></div>
<h3 id="The___complete__Modifier">The <span class="code-inline">#complete</span> Modifier</h3>
<p>Write <span class="code-inline">switch #complete</span> when matching enums to enforce exhaustive case handling. Every declared enum value must have a <span class="code-inline">case</span>, and the switch cannot have a <span class="code-inline">default</span>.</p>
<p><span class="code-inline">#complete</span> is a modifier and not an attribute because it selects a variant of <b>this one statement</b>: a statement carries no symbol, so there is nothing for an attribute to annotate or for reflection to report.</p>
<p><span class="code-inline">#static switch</span> accepts it too, with the same meaning and the same two rules: every declared enum value needs a <span class="code-inline">case</span>, and a <span class="code-inline">default</span> is rejected.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">enum</span> <span class="SCst">Color</span> { <span class="SCst">Red</span>, <span class="SCst">Green</span>, <span class="SCst">Blue</span> }
    <span class="SKwd">let</span> color = <span class="SCst">Color</span>.<span class="SCst">Red</span>

    <span class="SLgc">switch</span> <span class="SItr">#complete</span> color
    {
    <span class="SLgc">case</span> .<span class="SCst">Red</span>:   <span class="SLgc">break</span>
    <span class="SLgc">case</span> .<span class="SCst">Green</span>: <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    <span class="SLgc">case</span> .<span class="SCst">Blue</span>:  <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    }
}

</span></div>
<h3 id="Matching_Ranges_in_a__switch__Statement">Matching Ranges in a <span class="code-inline">switch</span> Statement</h3>
<p>Swag supports matching a <b>range of values</b> in <span class="code-inline">case</span> conditions for concise range-based logic.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> success = <span class="SKwd">false</span>
    <span class="SKwd">let</span> x       = <span class="SNum">6</span>

    <span class="SLgc">switch</span> x
    {
    <span class="SLgc">case</span> <span class="SNum">0</span> <span class="SLgc">to</span> <span class="SNum">5</span>:  <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    <span class="SLgc">case</span> <span class="SNum">6</span> <span class="SLgc">to</span> <span class="SNum">15</span>: success = <span class="SKwd">true</span>
    }

    <span class="SItr">@assert</span>(success)
}

</span></div>
<h3 id="Overlapping_Ranges">Overlapping Ranges</h3>
<p>When ranges overlap, the <b>first matching range</b> is executed; later overlaps are ignored.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> success = <span class="SKwd">false</span>
    <span class="SKwd">let</span> x       = <span class="SNum">6</span>

    <span class="SLgc">switch</span> x
    {
    <span class="SLgc">case</span> <span class="SNum">0</span> <span class="SLgc">to</span> <span class="SNum">10</span>:    success = <span class="SKwd">true</span>
    <span class="SLgc">case</span> <span class="SNum">5</span> <span class="SLgc">until</span> <span class="SNum">15</span>: <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    }

    <span class="SItr">@assert</span>(success)
}

</span></div>
<h3 id="Using_the__where__Clause_in__switch_">Using the <span class="code-inline">where</span> Clause in <span class="code-inline">switch</span></h3>
<p>Add a <span class="code-inline">where</span> clause to a <span class="code-inline">case</span> to refine matching conditions based on additional logic.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> x = <span class="SNum">6</span>
    <span class="SKwd">let</span> y = <span class="SNum">10</span>

    <span class="SLgc">switch</span> x
    {
    <span class="SLgc">case</span> <span class="SNum">6</span> <span class="SLgc">where</span> y == <span class="SNum">9</span>:  <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    <span class="SLgc">case</span> <span class="SNum">6</span> <span class="SLgc">where</span> y == <span class="SNum">10</span>: <span class="SItr">@assert</span>(<span class="SKwd">true</span>)
    <span class="SLgc">default</span>:              <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    }
}

</span></div>
<h3 id="Using__where__with__default_">Using <span class="code-inline">where</span> with <span class="code-inline">default</span></h3>
<p>A <span class="code-inline">where</span> clause can also modify the <span class="code-inline">default</span> case for conditional fallbacks.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> x = <span class="SNum">7</span>
    <span class="SKwd">let</span> y = <span class="SNum">10</span>
    <span class="SLgc">switch</span> x
    {
    <span class="SLgc">case</span> <span class="SNum">6</span> <span class="SLgc">where</span> y == <span class="SNum">10</span>:  <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    <span class="SLgc">case</span> <span class="SNum">7</span> <span class="SLgc">where</span> y == <span class="SNum">9</span>:   <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    <span class="SLgc">default</span> <span class="SLgc">where</span> y == <span class="SNum">10</span>: <span class="SLgc">break</span>
    <span class="SLgc">default</span>:               <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    }
}

</span></div>
<h3 id="Switching_on_Type_with__any__or__interface_">Switching on Type with <span class="code-inline">any</span> or <span class="code-inline">interface</span></h3>
<p>When switching on <span class="code-inline">any</span> or <span class="code-inline">interface</span> types, cases match based on the <b>underlying runtime type</b>.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> x: <span class="STpe">any</span> = <span class="SStr">"value"</span>
    <span class="SLgc">switch</span> x
    {
    <span class="SLgc">case</span> <span class="STpe">string</span>: <span class="SLgc">break</span>
    <span class="SLgc">default</span>:     <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    }
}

</span></div>
<h3 id="Switch_Statement_with_Type_Guard_and_Variable_Binding">Switch Statement with Type Guard and Variable Binding</h3>
<p>You can bind a matched type or value to a variable using <span class="code-inline">as</span>, allowing direct access inside the <span class="code-inline">case</span> block. You may also use <span class="code-inline">where</span> for conditional refinement.</p>
<div class="code-block"><span class="SCde">
</span></div>
<p>Example 1: Simple Type Binding</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> x: <span class="STpe">any</span> = <span class="SStr">"value"</span>
    <span class="SLgc">switch</span> x
    {
    <span class="SLgc">case</span> <span class="STpe">string</span> <span class="SLgc">as</span> str:
        <span class="SItr">@assert</span>(str == <span class="SStr">"value"</span>)
        <span class="SLgc">break</span>

    <span class="SLgc">default</span>:
        <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    }
}

</span></div>
<p>Example 2: Type Binding with <span class="code-inline">where</span> Clause</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> x: <span class="STpe">any</span> = <span class="SStr">"value"</span>
    <span class="SLgc">switch</span> x
    {
    <span class="SLgc">case</span> <span class="STpe">string</span> <span class="SLgc">as</span> str <span class="SLgc">where</span> str == <span class="SStr">"value"</span>:
        <span class="SItr">@assert</span>(str == <span class="SStr">"value"</span>)
        <span class="SLgc">break</span>

    <span class="SLgc">case</span> <span class="STpe">string</span> <span class="SLgc">as</span> str <span class="SLgc">where</span> str == <span class="SStr">"not_a_value"</span>:
        <span class="SItr">@assert</span>(str == <span class="SStr">"not_a_value"</span>)
        <span class="SLgc">break</span>

    <span class="SLgc">default</span>:
        <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    }
}

</span></div>
<h3 id="Switch_Without_an_Expression">Switch Without an Expression</h3>
<p>A <span class="code-inline">switch</span> without an expression behaves like an <span class="code-inline">if</span>/<span class="code-inline">elif</span> chain. Each <span class="code-inline">case</span> is evaluated in order, executing the first one that evaluates to <span class="code-inline">true</span>.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> value  = <span class="SNum">6</span>
    <span class="SKwd">let</span> value1 = <span class="SStr">"true"</span>

    <span class="SLgc">switch</span>
    {
    <span class="SLgc">case</span> value == <span class="SNum">6</span> <span class="SLgc">or</span> value &gt; <span class="SNum">10</span>:
        <span class="SItr">@assert</span>(<span class="SKwd">true</span>)
        <span class="SLgc">fallthrough</span>

    <span class="SLgc">case</span> value1 == <span class="SStr">"true"</span>:
        <span class="SItr">@assert</span>(<span class="SKwd">true</span>)

    <span class="SLgc">default</span>:
        <span class="SItr">@assert</span>(<span class="SKwd">false</span>)
    }
}

</span></div>
<h3 id="_005_006_break_swg">Break</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="The__break__Statement">The <span class="code-inline">break</span> Statement</h3>
<p>The <span class="code-inline">break</span> statement exits the nearest enclosing control structure. It works with <span class="code-inline">for</span>, <span class="code-inline">while</span>, and <span class="code-inline">switch</span>. Use it to stop a loop early or to leave a switch case.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SCmt">// Immediately exits the loop body</span>
    <span class="SLgc">for</span> <span class="SNum">10</span> <span class="SLgc">do</span>
        <span class="SLgc">break</span>

    <span class="SCmt">// Exits after the first iteration</span>
    <span class="SLgc">for</span> <span class="SKwd">var</span> i = <span class="SNum">0</span>; i &lt; <span class="SNum">10</span>; i += <span class="SNum">1</span> <span class="SLgc">do</span>
        <span class="SLgc">break</span>

    <span class="SCmt">// Not reached because the condition is false</span>
    <span class="SLgc">while</span> <span class="SKwd">false</span> <span class="SLgc">do</span>
        <span class="SLgc">break</span>
}

</span></div>
<h3 id="Default_Behavior">Default Behavior</h3>
<p>By default, <span class="code-inline">break</span> exits only the innermost loop or control structure. Outer structures continue to run.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> cpt = <span class="SNum">0</span>

    <span class="SLgc">for</span> <span class="SNum">10</span>
    {
        <span class="SLgc">for</span> <span class="SNum">10</span>
        {
            <span class="SCmt">// Exits only the inner loop</span>
            <span class="SLgc">break</span>
        }

        <span class="SCmt">// Outer loop continues</span>
        cpt += <span class="SNum">1</span>
    }

    <span class="SItr">@assert</span>(cpt == <span class="SNum">10</span>)
}

</span></div>
<h3 id="Named_Scopes_with___scope_">Named Scopes with <span class="code-inline">#scope</span></h3>
<p>Define a named scope with <span class="code-inline">#scope(Name)</span>. 'break to Name' exits that scope from anywhere inside it.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> cpt = <span class="SNum">0</span>

    <span class="SCmp">#scope</span>(<span class="SCst">BigScope</span>)
    {
        <span class="SLgc">for</span> <span class="SNum">10</span>
        {
            cpt += <span class="SNum">1</span>
            <span class="SLgc">break</span> <span class="SLgc">to</span> <span class="SCst">BigScope</span>     <span class="SCmt">// Leave the whole 'BigScope'</span>
        }

        <span class="SItr">@assert</span>(<span class="SKwd">false</span>)     <span class="SCmt">// Unreachable</span>
    }

    <span class="SItr">@assert</span>(cpt == <span class="SNum">1</span>)
}

</span></div>
<h3 id="Using__continue__with_Named_Scopes">Using <span class="code-inline">continue</span> with Named Scopes</h3>
<p>Within a scope, <span class="code-inline">continue</span> restarts execution from the beginning of that scope. Combine a terminating condition with a plain <span class="code-inline">break</span> to end the scope loop.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> cpt = <span class="SNum">0</span>

    <span class="SCmp">#scope</span>(<span class="SCst">Loop</span>)
    {
        cpt += <span class="SNum">1</span>
        <span class="SLgc">if</span> cpt == <span class="SNum">5</span> <span class="SLgc">do</span>
            <span class="SLgc">break</span>     <span class="SCmt">// End the 'Loop' scope</span>
        <span class="SLgc">continue</span>      <span class="SCmt">// Jump back to the start of 'Loop'</span>
    }

    <span class="SItr">@assert</span>(cpt == <span class="SNum">5</span>)
}

</span></div>
<h3 id="Unnamed_Scopes">Unnamed Scopes</h3>
<p>Scopes can be unnamed. <span class="code-inline">break</span> exits the current (unnamed) scope immediately. This can simplify multi-branch flows.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> cpt = <span class="SNum">0</span>

    <span class="SCmp">#scope</span>
    {
        <span class="SLgc">if</span> cpt == <span class="SNum">1</span>
        {
            <span class="SItr">@assert</span>(cpt == <span class="SNum">1</span>)
            <span class="SLgc">break</span>
        }

        <span class="SLgc">if</span> cpt == <span class="SNum">2</span>
        {
            <span class="SItr">@assert</span>(cpt == <span class="SNum">2</span>)
            <span class="SLgc">break</span>
        }

        <span class="SLgc">if</span> cpt == <span class="SNum">3</span>
        {
            <span class="SItr">@assert</span>(cpt == <span class="SNum">3</span>)
            <span class="SLgc">break</span>
        }
    }
}

</span></div>
<h3 id="Scopes_with_Simple_Statements">Scopes with Simple Statements</h3>
<p>A scope label can precede a simple statement. 'break to Label' exits to just after that labeled statement.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SCmp">#scope</span>(<span class="SCst">Up</span>)
        <span class="SLgc">for</span> <span class="SNum">10</span>
    {
        <span class="SLgc">for</span> <span class="SNum">10</span>
        {
            <span class="SLgc">if</span> <span class="SItr">@index</span> == <span class="SNum">5</span> <span class="SLgc">do</span>
                <span class="SLgc">break</span> <span class="SLgc">to</span> <span class="SCst">Up</span>     <span class="SCmt">// Exit to after the labeled 'for'</span>
        }

        <span class="SItr">@assert</span>(<span class="SKwd">false</span>)     <span class="SCmt">// Unreachable</span>
    }
}

</span></div>
<h2 id="_006_000_structs_swg">Structs</h2>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>
</span></div>
<p>Structs combine data with behavior through separate <span class="code-inline">impl</span> blocks. This chapter moves from declaration and layout to methods, generated operators, custom lifecycle hooks, iteration protocols, literals, and interfaces.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_006_001_declaration_swg">Declaration</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Basic_Struct_Declaration">Basic Struct Declaration</h3>
<p>This section illustrates a basic <span class="code-inline">struct</span> declaration in Swag. Notice that the <span class="code-inline">var</span> keyword is not required when declaring fields within the struct. Each field is defined with a specific type.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">struct</span> <span class="SCst">MyStruct</span>
    {
        name: <span class="SItr">#null</span> <span class="STpe">string</span>     <span class="SCmt">// Field 'name' of type 'string'</span>
    }

    <span class="SKwd">struct</span> <span class="SCst">MyStruct1</span>
    {
        x:    <span class="STpe">s32</span>          <span class="SCmt">// Field 'x' of type 's32'</span>
        y, z: <span class="STpe">s32</span>          <span class="SCmt">// Fields 'y' and 'z' of type 's32', declared together</span>
        val:  <span class="STpe">bool</span>         <span class="SCmt">// Field 'val' of type 'bool'</span>
        myS:  <span class="SCst">MyStruct</span>     <span class="SCmt">// Field 'myS' of type 'MyStruct', demonstrating a nested struct</span>
    }
}

</span></div>
<h3 id="Field_Separators">Field Separators</h3>
<p>Fields within a struct can be separated by either a comma <span class="code-inline">,</span> or a semicolon <span class="code-inline">;</span>. The trailing separator is optional and can be omitted.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SCmt">// Fields separated by commas</span>
    <span class="SKwd">struct</span> <span class="SCst">MyStruct</span>
    {
        name: <span class="SItr">#null</span> <span class="STpe">string</span>, val1: <span class="STpe">bool</span>
    }

    <span class="SKwd">struct</span> <span class="SCst">MyStruct1</span>
    {
        x: <span class="STpe">s32</span>, y, z: <span class="STpe">s32</span>, val: <span class="STpe">bool</span>, myS: <span class="SCst">MyStruct</span>
    }
}

</span></div>
<h3 id="Anonymous_Structs">Anonymous Structs</h3>
<p>Structs can be declared anonymously when used as variable types. This is particularly useful for lightweight, temporary groupings of data.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> tuple: <span class="SKwd">struct</span>
    {
        x: <span class="STpe">f32</span>     <span class="SCmt">// Field 'x' of type 'f32'</span>
        y: <span class="STpe">f32</span>     <span class="SCmt">// Field 'y' of type 'f32'</span>
    }

    <span class="SKwd">var</span> tuple1: <span class="SKwd">struct</span>
    {
        x, y: <span class="STpe">f32</span>     <span class="SCmt">// Anonymous struct with fields 'x' and 'y' of type 'f32'</span>
    }

    tuple.x = <span class="SNum">1.0</span>
    tuple.y = <span class="SNum">2.0</span>
    <span class="SItr">@assert</span>(tuple.x == <span class="SNum">1.0</span>)
    <span class="SItr">@assert</span>(tuple.y == <span class="SNum">2.0</span>)
}

<span class="SFct">#test</span>
{
    <span class="SKwd">struct</span> <span class="SCst">MyStruct</span>
    {
        rgb: <span class="SKwd">struct</span>
        {
            x, y, z: <span class="STpe">f32</span>     <span class="SCmt">// Nested anonymous struct for RGB values</span>
        }

        hsl: <span class="SKwd">struct</span>
        {
            h, s, l: <span class="STpe">f32</span>     <span class="SCmt">// Nested anonymous struct for HSL values</span>
        }
    }
}

</span></div>
<h3 id="Default_Field_Values">Default Field Values</h3>
<p>Fields within a struct can be initialized with default values, providing a convenient way to ensure fields are set to a known state.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">struct</span> <span class="SCst">MyStruct</span>
    {
        x: <span class="STpe">s32</span>    = <span class="SNum">666</span>       <span class="SCmt">// Field 'x' initialized with default value 666</span>
        y: <span class="STpe">string</span> = <span class="SStr">"454"</span>     <span class="SCmt">// Field 'y' initialized with default value '454'</span>
    }

    <span class="SKwd">let</span> v = <span class="SCst">MyStruct</span>{}     <span class="SCmt">// Initializing struct with default values</span>
    <span class="SItr">@assert</span>(v.x == <span class="SNum">666</span>)
    <span class="SItr">@assert</span>(v.y == <span class="SStr">"454"</span>)
}

</span></div>
<h3 id="Struct_Initialization">Struct Initialization</h3>
<p>Struct variables can be initialized in multiple ways, providing flexibility in how you set up your structs. Every form initializes with <span class="code-inline">=</span>: naming the type in the initializer (<span class="code-inline">MyStruct{...}</span>) or in the annotation ('let v: MyStruct = {...}') is a matter of where the type reads best, never of syntax.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">struct</span> <span class="SCst">MyStruct</span>
    {
        x, y: <span class="STpe">s32</span> = <span class="SNum">1</span>     <span class="SCmt">// Both 'x' and 'y' initialized to 1</span>
    }

    <span class="SCmt">// Default initialization</span>
    <span class="SKwd">let</span> v0: <span class="SCst">MyStruct</span>
    <span class="SItr">@assert</span>(v0.x == <span class="SNum">1</span>)
    <span class="SItr">@assert</span>(v0.y == <span class="SNum">1</span>)

    <span class="SCmt">// Positional initialization</span>
    <span class="SKwd">let</span> v1 = <span class="SCst">MyStruct</span>{<span class="SNum">10</span>, <span class="SNum">20</span>}
    <span class="SItr">@assert</span>(v1.x == <span class="SNum">10</span>)
    <span class="SItr">@assert</span>(v1.y == <span class="SNum">20</span>)

    <span class="SCmt">// Named initialization</span>
    <span class="SKwd">let</span> v2 = <span class="SCst">MyStruct</span>{y: <span class="SNum">20</span>}
    <span class="SItr">@assert</span>(v2.x == <span class="SNum">1</span>)
    <span class="SItr">@assert</span>(v2.y == <span class="SNum">20</span>)

    <span class="SCmt">// Tuple initialization</span>
    <span class="SKwd">let</span> v3: <span class="SCst">MyStruct</span> = {<span class="SNum">10</span>, <span class="SNum">20</span>}
    <span class="SItr">@assert</span>(v3.x == <span class="SNum">10</span>)
    <span class="SItr">@assert</span>(v3.y == <span class="SNum">20</span>)
}

</span></div>
<h3 id="Const_Structs">Const Structs</h3>
<p>A struct can be defined as a constant, provided its values can be evaluated at compile time. This ensures immutability throughout program execution.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">struct</span> <span class="SCst">MyStruct</span>
    {
        x: <span class="STpe">s32</span>    = <span class="SNum">666</span>
        y: <span class="STpe">string</span> = <span class="SStr">"454"</span>
    }

    <span class="SKwd">const</span> <span class="SCst">X</span> = <span class="SCst">MyStruct</span>{<span class="SNum">50</span>, <span class="SStr">"value"</span>}

    <span class="SCmp">#assert</span>(<span class="SCst">X</span>.x == <span class="SNum">50</span>)     <span class="SCmt">// Compile-time assertion</span>
    <span class="SCmp">#assert</span>(<span class="SCst">X</span>.y == <span class="SStr">"value"</span>)
}

</span></div>
<h3 id="Structs_as_Function_Arguments">Structs as Function Arguments</h3>
<p>Functions can take a struct as an argument. This is done by reference, with no copy made — equivalent to passing a const reference in C++.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">struct</span> <span class="SCst">Struct3</span>
{
    x, y, z: <span class="STpe">s32</span> = <span class="SNum">666</span>
}

<span class="SKwd">func</span> <span class="SFct">toto</span>(v: <span class="SCst">Struct3</span>)
{
    <span class="SItr">@assert</span>(v.x == <span class="SNum">5</span>)
    <span class="SItr">@assert</span>(v.y == <span class="SNum">5</span>)
    <span class="SItr">@assert</span>(v.z == <span class="SNum">666</span>)
}

<span class="SKwd">func</span> <span class="SFct">titi</span>(v: <span class="SCst">Struct3</span>)
{
    <span class="SItr">@assert</span>(v.x == <span class="SNum">5</span>)
    <span class="SItr">@assert</span>(v.y == <span class="SNum">666</span>)
}

<span class="SFct">#test</span>
{
    <span class="SCmt">// Calling with explicit values</span>
    <span class="SFct">toto</span>(<span class="SCst">Struct3</span>{<span class="SNum">5</span>, <span class="SNum">5</span>, <span class="SNum">666</span>})

    <span class="SCmt">// Type inferred from arguments</span>
    <span class="SFct">toto</span>({<span class="SNum">5</span>, <span class="SNum">5</span>, <span class="SNum">666</span>})

    <span class="SCmt">// Partial initialization</span>
    <span class="SFct">titi</span>({<span class="SNum">5</span>})
    <span class="SFct">titi</span>({<span class="SNum">5</span>, <span class="SNum">666</span>})

    <span class="SCmt">// Named field initialization</span>
    <span class="SFct">titi</span>({x: <span class="SNum">5</span>, z: <span class="SNum">5</span>})
}

</span></div>
<h3 id="_006_002_impl_swg">Impl</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Struct_Methods_and_Constants">Struct Methods and Constants</h3>
<p>In Swag, structs can encapsulate methods and constants within them using the <span class="code-inline">impl</span> block. This keeps related functionality close to the data it operates on.</p>
<div class="code-block"><span class="SCde">
<span class="SAtr">#[Swag.ExportType(.Methods)]</span>     <span class="SCmt">// Enable method reflection for this struct type</span>
<span class="SKwd">struct</span> <span class="SCst">MyStruct</span>
{
    x: <span class="STpe">s32</span> = <span class="SNum">5</span>      <span class="SCmt">// Default 5</span>
    y: <span class="STpe">s32</span> = <span class="SNum">10</span>     <span class="SCmt">// Default 10</span>
    z: <span class="STpe">s32</span> = <span class="SNum">20</span>     <span class="SCmt">// Default 20</span>
}

<span class="SKwd">impl</span> <span class="SCst">MyStruct</span>
{
    <span class="SKwd">const</span> <span class="SCst">MyConst</span> = <span class="SKwd">true</span>     <span class="SCmt">// Constant in the struct's namespace</span>

    <span class="SKwd">func</span> <span class="SFct">returnTrue</span>() =&gt; <span class="SKwd">true</span>
}

</span></div>
<p>To access the constant or the function, use the <span class="code-inline">MyStruct</span> namespace.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SItr">@assert</span>(<span class="SCst">MyStruct</span>.<span class="SCst">MyConst</span>)
    <span class="SItr">@assert</span>(<span class="SCst">MyStruct</span>.<span class="SFct">returnTrue</span>())
}

</span></div>
<h3 id="Multiple__impl__Blocks">Multiple <span class="code-inline">impl</span> Blocks</h3>
<p>Swag allows multiple <span class="code-inline">impl</span> blocks for the same struct. Inside methods, <span class="code-inline">me</span> refers to the current instance. You can also name the receiver explicitly.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">impl</span> <span class="SCst">MyStruct</span>
{
    <span class="SCmt">// 'me' is implicitly 'var me: MyStruct'</span>
    <span class="SKwd">func</span> <span class="SFct">returnX</span>(<span class="STpe">me</span>) =&gt; <span class="STpe">me</span>.x
    <span class="SKwd">func</span> <span class="SFct">returnY</span>(<span class="STpe">me</span>) =&gt; <span class="STpe">me</span>.y

    <span class="SCmt">// Explicit receiver name and type</span>
    <span class="SKwd">func</span> <span class="SFct">returnZ</span>(self: <span class="SCst">MyStruct</span>) =&gt; self.z
}

</span></div>
<h3 id="Method_Syntax_Sugar">Method Syntax Sugar</h3>
<p>Using <span class="code-inline">mtd</span> makes the first parameter implicitly <span class="code-inline">me</span>. Using 'mtd const' makes it 'const me'. This simplifies common patterns.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">impl</span> <span class="SCst">MyStruct</span>
{
    <span class="SKwd">mtd</span> <span class="SFct">methodReturnX</span>()  =&gt; <span class="STpe">me</span>.x     <span class="SCmt">// Equivalent to 'func methodReturnX(me) =&gt; me.x'</span>
    <span class="SKwd">func</span> <span class="SFct">funcReturnX</span>(<span class="STpe">me</span>) =&gt; <span class="STpe">me</span>.x
    <span class="SKwd">func</span> <span class="SFct">funcReturnY</span>(<span class="STpe">me</span>) =&gt; .x     <span class="SCmt">// 'me' can be omitted</span>
}

<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> c: <span class="SCst">MyStruct</span>

    <span class="SItr">@assert</span>(c.<span class="SFct">returnX</span>() == <span class="SNum">5</span>)
    <span class="SItr">@assert</span>(c.<span class="SFct">methodReturnX</span>() == <span class="SNum">5</span>)
    <span class="SItr">@assert</span>(c.<span class="SFct">funcReturnX</span>() == <span class="SNum">5</span>)
    <span class="SItr">@assert</span>(c.<span class="SFct">returnY</span>() == <span class="SNum">10</span>)
    <span class="SItr">@assert</span>(c.<span class="SFct">returnZ</span>() == <span class="SNum">20</span>)
}

</span></div>
<h3 id="Method_Reflection">Method Reflection</h3>
<p>To enable reflection on methods in an <span class="code-inline">impl</span> block, annotate the struct with <span class="code-inline">#[Swag.ExportType(.Methods)]</span>. The <span class="code-inline">typeinfo</span> for the struct then exposes a <span class="code-inline">methods</span> slice. Each <span class="code-inline">Swag.TypeValue</span> supplies the method name, function type, attributes, and—when callable at runtime—the function pointer.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">alias</span> <span class="SCst">ReflectedMyStructMethod</span> = <span class="SKwd">func</span>(&amp;<span class="SCst">MyStruct</span>)-&gt;<span class="STpe">s32</span>

<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> type    = <span class="SKwd">cast</span>(<span class="SKwd">const</span> *<span class="SCst">Swag</span>.<span class="SCst">TypeInfoStruct</span>) <span class="SItr">#type</span> <span class="SCst">MyStruct</span>
    <span class="SKwd">let</span> methods = <span class="SKwd">notnull</span> type.methods
    <span class="SKwd">var</span> returnX: <span class="SItr">#null</span> <span class="SKwd">const</span> *<span class="SCst">Swag</span>.<span class="SCst">TypeValue</span>

    <span class="SLgc">for</span> &amp;method <span class="SLgc">in</span> methods
    {
        <span class="SLgc">if</span> method.name == <span class="SStr">"returnX"</span>
        {
            returnX = &amp;method
            <span class="SLgc">break</span>
        }
    }

    <span class="SItr">@assert</span>(returnX != <span class="SKwd">null</span>)
    <span class="SKwd">let</span> method = <span class="SKwd">notnull</span> returnX
    <span class="SItr">@assert</span>((<span class="SKwd">notnull</span> method.pointedType).kind == .<span class="SCst">Func</span>)

    <span class="SKwd">let</span> call = <span class="SKwd">cast</span>(<span class="SCst">ReflectedMyStructMethod</span>) <span class="SKwd">notnull</span> method.value
    <span class="SKwd">var</span> value: <span class="SCst">MyStruct</span>
    <span class="SItr">@assert</span>(<span class="SFct">call</span>(&amp;value) == <span class="SNum">5</span>)
}

</span></div>
<h3 id="_006_003_offset_swg">Offset</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Custom_Field_Layout_with__Swag_Offset_">Custom Field Layout with <span class="code-inline">Swag.Offset</span></h3>
<p>You can force the layout of a field within a struct using the <span class="code-inline">Swag.Offset</span> attribute. This lets you manually specify the memory offset of a field — useful for custom memory layouts, such as overlapping fields or sharing memory space between fields.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">struct</span> <span class="SCst">MyStruct</span>
    {
        x: <span class="STpe">s32</span>

        <span class="SCmt">// 'y' is located at the same offset as 'x', so they share the same memory.</span>
        <span class="SCmt">// Changing one reflects in the other (overlay behavior).</span>
        <span class="SAtr">#[Swag.Offset("x")]</span>
        y: <span class="STpe">s32</span>
    }

    <span class="SCmt">// Even with two fields, they overlap, so the struct uses only 4 bytes.</span>
    <span class="SCmp">#assert</span>(<span class="SItr">#sizeof</span>(<span class="SCst">MyStruct</span>) == <span class="SNum">4</span>)

    <span class="SKwd">var</span> v = <span class="SCst">MyStruct</span>{}
    v.x = <span class="SNum">666</span>

    <span class="SCmt">// Since 'x' and 'y' share memory, updating 'x' updates 'y'.</span>
    <span class="SItr">@assert</span>(v.y == <span class="SNum">666</span>)
}

</span></div>
<h3 id="Using__Swag_Offset__for_Indexed_Field_Access">Using <span class="code-inline">Swag.Offset</span> for Indexed Field Access</h3>
<p>Here, <span class="code-inline">Swag.Offset</span> is used so an indexed array aliases multiple fields, enabling indexed access to those fields via a single view.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">struct</span> <span class="SCst">MyStruct</span>
    {
        x, y, z: <span class="STpe">f32</span>

        <span class="SCmt">// 'idx' aliases the same memory as 'x', 'y', and 'z'.</span>
        <span class="SCmt">// Access 'x', 'y', and 'z' through indexed reads/writes on 'idx'.</span>
        <span class="SAtr">#[Swag.Offset("x")]</span>
        idx: [<span class="SNum">3</span>] <span class="STpe">f32</span>
    }

    <span class="SKwd">var</span> v: <span class="SCst">MyStruct</span>
    v.x = <span class="SNum">10</span>; v.y = <span class="SNum">20</span>; v.z = <span class="SNum">30</span>

    <span class="SCmt">// Each index in 'idx' maps directly to x/y/z.</span>
    <span class="SItr">@assert</span>(v.idx[<span class="SNum">0</span>] == v.x)
    <span class="SItr">@assert</span>(v.idx[<span class="SNum">1</span>] == v.y)
    <span class="SItr">@assert</span>(v.idx[<span class="SNum">2</span>] == v.z)
}

</span></div>
<h3 id="_006_004_packing_swg">Packing</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Default_Struct_Packing">Default Struct Packing</h3>
<p>By default, Swag aligns struct fields similarly to the C programming language. Each field is aligned based on the size of its type, ensuring optimal memory access. This default behavior can be explicitly specified using <span class="code-inline">#[Swag.Pack(0)]</span>, meaning no additional packing adjustments are applied. Below is an example illustrating this default alignment strategy.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">struct</span> <span class="SCst">MyStruct</span>
    {
        x: <span class="STpe">bool</span>     <span class="SCmt">// offset 0: aligned to 1 byte (no padding needed)</span>
        y: <span class="STpe">s32</span>      <span class="SCmt">// offset 4: aligned to 4 bytes (3 bytes of padding before y)</span>
        z: <span class="STpe">s64</span>      <span class="SCmt">// offset 8: aligned to 8 bytes (no padding needed)</span>
    }

    <span class="SCmp">#assert</span>(<span class="SItr">#offsetof</span>(<span class="SCst">MyStruct</span>.x) == <span class="SNum">0</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#offsetof</span>(<span class="SCst">MyStruct</span>.y) == <span class="SNum">4</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#offsetof</span>(<span class="SCst">MyStruct</span>.z) == <span class="SNum">8</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#sizeof</span>(<span class="SCst">MyStruct</span>) == <span class="SNum">16</span>)
}

</span></div>
<h3 id="Reducing_Packing">Reducing Packing</h3>
<p>Swag allows reducing the packing of struct fields using the <span class="code-inline">#[Swag.Pack]</span> attribute. This attribute specifies the alignment value applied to each field, enabling more compact struct representations. Below are examples demonstrating different levels of packing.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SAtr">#[Swag.Pack(1)]</span>
    <span class="SKwd">struct</span> <span class="SCst">MyStruct1</span>
    {
        x: <span class="STpe">bool</span>     <span class="SCmt">// offset 0: 1 byte (no padding)</span>
        y: <span class="STpe">s32</span>      <span class="SCmt">// offset 1: 4 bytes (no padding)</span>
    }

    <span class="SCmp">#assert</span>(<span class="SItr">#offsetof</span>(<span class="SCst">MyStruct1</span>.x) == <span class="SNum">0</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#offsetof</span>(<span class="SCst">MyStruct1</span>.y) == <span class="SNum">1</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#sizeof</span>(<span class="SCst">MyStruct1</span>) == <span class="SNum">5</span>)

    <span class="SAtr">#[Swag.Pack(2)]</span>
    <span class="SKwd">struct</span> <span class="SCst">MyStruct2</span>
    {
        x: <span class="STpe">bool</span>     <span class="SCmt">// offset 0: 1 byte</span>
        y: <span class="STpe">s32</span>      <span class="SCmt">// offset 2: 4 bytes (1 byte of padding before y)</span>
    }

    <span class="SCmp">#assert</span>(<span class="SItr">#offsetof</span>(<span class="SCst">MyStruct2</span>.x) == <span class="SNum">0</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#offsetof</span>(<span class="SCst">MyStruct2</span>.y) == <span class="SNum">2</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#sizeof</span>(<span class="SCst">MyStruct2</span>) == <span class="SNum">6</span>)

    <span class="SAtr">#[Swag.Pack(4)]</span>
    <span class="SKwd">struct</span> <span class="SCst">MyStruct3</span>
    {
        x: <span class="STpe">bool</span>     <span class="SCmt">// offset 0: 1 byte</span>
        y: <span class="STpe">s64</span>      <span class="SCmt">// offset 4: 8 bytes (3 bytes of padding before y)</span>
    }

    <span class="SCmp">#assert</span>(<span class="SItr">#offsetof</span>(<span class="SCst">MyStruct3</span>.x) == <span class="SNum">0</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#offsetof</span>(<span class="SCst">MyStruct3</span>.y) == <span class="SNum">4</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#sizeof</span>(<span class="SCst">MyStruct3</span>) == <span class="SNum">12</span>)
}

</span></div>
<h3 id="Struct_Size_and_Alignment">Struct Size and Alignment</h3>
<p>The total size of a struct in Swag is always a multiple of the largest alignment value among its fields. This ensures correct alignment when used within larger data structures or arrays.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">struct</span> <span class="SCst">MyStruct1</span>
    {
        x: <span class="STpe">s32</span>      <span class="SCmt">// 4 bytes</span>
        y: <span class="STpe">bool</span>     <span class="SCmt">// 1 byte</span>
    <span class="SCmt">// 3 bytes of padding to align to s32 size</span>
    }

    <span class="SCmp">#assert</span>(<span class="SItr">#sizeof</span>(<span class="SCst">MyStruct1</span>) == <span class="SNum">8</span>)
}

</span></div>
<h3 id="Enforcing_Alignment_with__Swag_Align_">Enforcing Alignment with <span class="code-inline">Swag.Align</span></h3>
<p>Swag provides the <span class="code-inline">#[Swag.Align]</span> attribute to enforce specific alignment constraints on an entire struct. Use it to meet hardware or performance requirements.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">struct</span> <span class="SCst">MyStruct1</span>
    {
        x: <span class="STpe">bool</span>     <span class="SCmt">// 1 byte</span>
        y: <span class="STpe">bool</span>     <span class="SCmt">// 1 byte</span>
    }

    <span class="SCmp">#assert</span>(<span class="SItr">#offsetof</span>(<span class="SCst">MyStruct1</span>.x) == <span class="SNum">0</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#offsetof</span>(<span class="SCst">MyStruct1</span>.y) == <span class="SNum">1</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#sizeof</span>(<span class="SCst">MyStruct1</span>) == <span class="SNum">2</span>)

    <span class="SAtr">#[Swag.Align(8)]</span>
    <span class="SKwd">struct</span> <span class="SCst">MyStruct2</span>
    {
        x: <span class="STpe">bool</span>     <span class="SCmt">// 1 byte</span>
        y: <span class="STpe">bool</span>     <span class="SCmt">// 1 byte</span>
    <span class="SCmt">// 6 bytes of padding to align struct size to 8</span>
    }

    <span class="SCmp">#assert</span>(<span class="SItr">#offsetof</span>(<span class="SCst">MyStruct2</span>.x) == <span class="SNum">0</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#offsetof</span>(<span class="SCst">MyStruct2</span>.y) == <span class="SNum">1</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#sizeof</span>(<span class="SCst">MyStruct2</span>) == <span class="SNum">8</span>)
}

</span></div>
<h3 id="Field-Specific_Alignment">Field-Specific Alignment</h3>
<p>Set specific alignment values for individual fields using the <span class="code-inline">#[Swag.Align]</span> attribute. This provides fine-grained control over memory layout for low-level optimizations.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">struct</span> <span class="SCst">MyStruct1</span>
    {
        x: <span class="STpe">bool</span>     <span class="SCmt">// offset 0: 1 byte</span>
        <span class="SAtr">#[Swag.Align(8)]</span>
        y: <span class="STpe">bool</span>     <span class="SCmt">// offset 8: aligned to 8 bytes (7 bytes of padding before y)</span>
    }

    <span class="SCmp">#assert</span>(<span class="SItr">#offsetof</span>(<span class="SCst">MyStruct1</span>.x) == <span class="SNum">0</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#offsetof</span>(<span class="SCst">MyStruct1</span>.y) == <span class="SNum">8</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#sizeof</span>(<span class="SCst">MyStruct1</span>) == <span class="SNum">16</span>)

    <span class="SAtr">#[Swag.Align(8)]</span>
    <span class="SKwd">struct</span> <span class="SCst">MyStruct2</span>
    {
        x: <span class="STpe">bool</span>     <span class="SCmt">// offset 0: 1 byte</span>
        <span class="SAtr">#[Swag.Align(4)]</span>
        y: <span class="STpe">bool</span>     <span class="SCmt">// offset 4: aligned to 4 bytes (3 bytes of padding before y)</span>
    <span class="SCmt">// 3 bytes of padding to align struct size to 8</span>
    }

    <span class="SCmp">#assert</span>(<span class="SItr">#offsetof</span>(<span class="SCst">MyStruct2</span>.x) == <span class="SNum">0</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#offsetof</span>(<span class="SCst">MyStruct2</span>.y) == <span class="SNum">4</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#sizeof</span>(<span class="SCst">MyStruct2</span>) == <span class="SNum">8</span>)
}

</span></div>
<h3 id="_006_005_operator_overloading_swg">Operator Overloading</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<p>A struct in Swag can define operator overloads within the <span class="code-inline">impl</span> block. These hooks are predefined and recognized by the compiler, which lets a struct customize operators and core interactions.</p>
<p><span class="code-inline">opBinary</span>, <span class="code-inline">opBinaryRight</span>, <span class="code-inline">opUnary</span>, <span class="code-inline">opAssign</span> and <span class="code-inline">opIndexAssign</span> take the operator as a compile-time <span class="code-inline">Swag.Operator</span> value, so one hook covers a whole family and a misspelled member is reported instead of being a comparison that silently never matches. Each spelling has its own member: unary <span class="code-inline">-</span> arrives as <span class="code-inline">Neg</span>, binary <span class="code-inline">-</span> as <span class="code-inline">Sub</span>. <span class="code-inline">op.symbol()</span> returns the source spelling when generated code or a diagnostic needs it.</p>
<p>An operator body is compiled for the requested operator with diagnostics on, with a single exception: <span class="code-inline">#error</span> is the sanctioned way to say "this overload does not handle that operator", so it is silenced and the overload is simply skipped. Every other failure in the body is reported where it occurs.</p>
<p>A literal suffix stays a string (<span class="code-inline">opSetLiteral</span>), because the set of suffixes is open-ended and chosen by the user rather than by the language.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">struct</span> <span class="SCst">Struct</span>
{
    x, y: <span class="STpe">s32</span>     <span class="SCmt">// Two properties, x and y, of type s32 (signed 32-bit integer)</span>
}

<span class="SCmt">// Type aliases used in the examples below</span>
<span class="SKwd">alias</span> <span class="SCst">OneType</span>      = <span class="STpe">bool</span>     <span class="SCmt">// Alias for boolean type</span>
<span class="SKwd">alias</span> <span class="SCst">AnotherType</span>  = <span class="STpe">s32</span>      <span class="SCmt">// Alias for signed 32-bit integer type</span>
<span class="SKwd">alias</span> <span class="SCst">WhateverType</span> = <span class="STpe">bool</span>     <span class="SCmt">// Another alias for boolean type</span>

<span class="SAtr">#[Swag.Operators(opEquals, opCompare)]</span>
<span class="SKwd">struct</span> <span class="SCst">AutoComparable</span>
{
    x, y: <span class="STpe">s32</span>
    <span class="SAtr">#[Swag.OperatorIgnore]</span>
    cachedHash: <span class="STpe">u64</span>
}

<span class="SAtr">#[Swag.Operators(opEquals, opCompare)]</span>
<span class="SKwd">struct</span>(<span class="SCst">T</span>) <span class="SCst">AutoComparableBox</span>
{
    value: <span class="SCst">T</span>
}

<span class="SCmt">// Implementation: lifecycle, accessors, conversions, comparisons, assignments,</span>
<span class="SCmt">// indexing, binary/unary operators, and iteration hooks</span>
<span class="SKwd">impl</span> <span class="SCst">Struct</span>
{
    <span class="SCmt">// -------------------------------------------------------------------------</span>
    <span class="SCmt">// Lifecycle hooks</span>
    <span class="SCmt">// -------------------------------------------------------------------------</span>

    <span class="SCmt">// Called whenever a variable of this struct is about to be destroyed (C++ destructor-like)</span>
    <span class="SKwd">func</span> <span class="SFct">opDrop</span>(<span class="STpe">me</span>) {}

    <span class="SCmt">// Invoked after a raw copy operation has been performed from one value to another</span>
    <span class="SKwd">func</span> <span class="SFct">opPostCopy</span>(<span class="STpe">me</span>) {}

    <span class="SCmt">// Called after a move semantic operation has been executed from one value to another</span>
    <span class="SKwd">func</span> <span class="SFct">opPostMove</span>(<span class="STpe">me</span>) {}

    <span class="SCmt">// -------------------------------------------------------------------------</span>
    <span class="SCmt">// Element &amp; slice access</span>
    <span class="SCmt">// -------------------------------------------------------------------------</span>

    <span class="SCmt">// Access a value by slicing with the [low..up] notation. Returns a string or a slice.</span>
    <span class="SKwd">func</span> <span class="SFct">opSlice</span>(<span class="STpe">me</span>, low, up: <span class="STpe">u64</span>)-&gt;<span class="STpe">string</span>
    {
        <span class="SLgc">return</span> <span class="SStr">"true"</span>
    }

    <span class="SCmt">// Access a value by one or more indices. All index parameters must have the same type.</span>
    <span class="SKwd">func</span> <span class="SFct">opIndex</span>(<span class="STpe">me</span>, index: <span class="SCst">OneType</span>)-&gt;<span class="SCst">WhateverType</span>
    {
        <span class="SLgc">return</span> <span class="SKwd">true</span>
    }

    <span class="SKwd">func</span> <span class="SFct">opIndex</span>(<span class="STpe">me</span>, row: <span class="SCst">OneType</span>, column: <span class="SCst">OneType</span>)-&gt;<span class="SCst">WhateverType</span>
    {
        <span class="SLgc">return</span> <span class="SKwd">true</span>
    }

    <span class="SCmt">// Called when @countof is used (typically in a 'for' block) to return the count of elements</span>
    <span class="SKwd">func</span> <span class="SFct">opCount</span>(<span class="STpe">me</span>)-&gt;<span class="STpe">u64</span>
    {
        <span class="SLgc">return</span> <span class="SNum">0</span>
    }

    <span class="SCmt">// Called when @dataof is used; returns a pointer to the underlying data of type WhateverType</span>
    <span class="SKwd">func</span> <span class="SFct">opData</span>(<span class="STpe">me</span>)-&gt;<span class="SItr">#null</span> *<span class="SCst">WhateverType</span>
    {
        <span class="SLgc">return</span> <span class="SKwd">null</span>
    }

    <span class="SCmt">// -------------------------------------------------------------------------</span>
    <span class="SCmt">// Conversions (cast)</span>
    <span class="SCmt">// -------------------------------------------------------------------------</span>

    <span class="SCmt">// Custom casting between the struct and another type; can be overloaded with different return types</span>
    <span class="SCmt">// Example: var x = cast(OneType) v</span>
    <span class="SKwd">func</span> <span class="SFct">opCast</span>(<span class="STpe">me</span>)-&gt;<span class="SCst">OneType</span>
    {
        <span class="SLgc">return</span> <span class="SKwd">true</span>
    }

    <span class="SKwd">func</span> <span class="SFct">opCast</span>(<span class="STpe">me</span>)-&gt;<span class="SCst">AnotherType</span>
    {
        <span class="SLgc">return</span> <span class="SNum">0</span>
    }

    <span class="SCmt">// -------------------------------------------------------------------------</span>
    <span class="SCmt">// Equality &amp; ordering</span>
    <span class="SCmt">// -------------------------------------------------------------------------</span>

    <span class="SCmt">// Compare the struct value with another; used in '==' and '!=' operations</span>
    <span class="SKwd">func</span> <span class="SFct">opEquals</span>(<span class="STpe">me</span>, other: <span class="SCst">OneType</span>)-&gt;<span class="STpe">bool</span>
    {
        <span class="SLgc">return</span> <span class="SKwd">false</span>
    }

    <span class="SKwd">func</span> <span class="SFct">opEquals</span>(<span class="STpe">me</span>, other: <span class="SCst">AnotherType</span>)-&gt;<span class="STpe">bool</span>
    {
        <span class="SLgc">return</span> <span class="SKwd">false</span>
    }

    <span class="SCmt">// Three-way comparison; returns -1, 0, or 1 (used for '&lt;', '&gt;', '&lt;=', '&gt;=', '&lt;=&gt;')</span>
    <span class="SKwd">func</span> <span class="SFct">opCompare</span>(<span class="STpe">me</span>, other: <span class="SCst">OneType</span>)-&gt;<span class="STpe">s32</span>
    {
        <span class="SLgc">return</span> <span class="SNum">0</span>
    }

    <span class="SKwd">func</span> <span class="SFct">opCompare</span>(<span class="STpe">me</span>, other: <span class="SCst">AnotherType</span>)-&gt;<span class="STpe">s32</span>
    {
        <span class="SLgc">return</span> <span class="SNum">0</span>
    }

    <span class="SCmt">// -------------------------------------------------------------------------</span>
    <span class="SCmt">// Assignment</span>
    <span class="SCmt">// -------------------------------------------------------------------------</span>

    <span class="SCmt">// Direct assignment via '='</span>
    <span class="SKwd">func</span> <span class="SFct">opSet</span>(<span class="STpe">me</span>, other: <span class="SCst">OneType</span>) {}
    <span class="SKwd">func</span> <span class="SFct">opSet</span>(<span class="STpe">me</span>, other: <span class="SCst">AnotherType</span>) {}

    <span class="SCmt">// Assign a literal value with a specific suffix to the struct (generic)</span>
    <span class="SKwd">func</span>(suffix: <span class="STpe">string</span>) <span class="SFct">opSetLiteral</span>(<span class="STpe">me</span>, value: <span class="SCst">OneType</span>) {}
    <span class="SKwd">func</span>(suffix: <span class="STpe">string</span>) <span class="SFct">opSetLiteral</span>(<span class="STpe">me</span>, value: <span class="SCst">AnotherType</span>) {}

    <span class="SCmt">// Assign to an indexed position via '[?] ='. All index parameters must have the same type.</span>
    <span class="SCmt">// When both opIndexSet and opIndex can write, opIndexSet is selected.</span>
    <span class="SKwd">func</span> <span class="SFct">opIndexSet</span>(<span class="STpe">me</span>, index: <span class="SCst">OneType</span>, value: <span class="SCst">OneType</span>) {}
    <span class="SKwd">func</span> <span class="SFct">opIndexSet</span>(<span class="STpe">me</span>, row: <span class="SCst">OneType</span>, column: <span class="SCst">OneType</span>, value: <span class="SCst">OneType</span>) {}
    <span class="SKwd">func</span> <span class="SFct">opIndexSet</span>(<span class="STpe">me</span>, index: <span class="SCst">OneType</span>, value: <span class="SCst">AnotherType</span>) {}

    <span class="SCmt">// -------------------------------------------------------------------------</span>
    <span class="SCmt">// Operators (binary, unary, compound assignment)</span>
    <span class="SCmt">// -------------------------------------------------------------------------</span>

    <span class="SCmt">// Binary operation. 'op' is the 'Swag.Operator' member the compiler asks for:</span>
    <span class="SCmt">// Add, Sub, Mul, Div, Mod, BitOr, BitAnd, BitXor, Shl, Shr</span>
    <span class="SKwd">func</span>(op: <span class="SCst">Swag</span>.<span class="SCst">Operator</span>) <span class="SFct">opBinary</span>(<span class="STpe">me</span>, other: <span class="SCst">OneType</span>)-&gt;<span class="SCst">Struct</span>
    {
        <span class="SCmp">#static</span> <span class="SLgc">switch</span> op
        {
        <span class="SLgc">case</span> .<span class="SCst">Add</span>: <span class="SLgc">return</span> {<span class="SNum">1</span>, <span class="SNum">2</span>}
        <span class="SLgc">case</span> .<span class="SCst">Sub</span>: <span class="SLgc">return</span> {<span class="SNum">2</span>, <span class="SNum">1</span>}
        <span class="SLgc">default</span>:   <span class="SCmp">#error</span>(<span class="SStr">"unsupported binary operation"</span>)
        }
    }

    <span class="SKwd">func</span>(op: <span class="SCst">Swag</span>.<span class="SCst">Operator</span>) <span class="SFct">opBinary</span>(<span class="STpe">me</span>, other: <span class="SCst">AnotherType</span>)-&gt;<span class="SCst">Struct</span>
    {
        <span class="SLgc">return</span> {<span class="SNum">1</span>, <span class="SNum">2</span>}
    }

    <span class="SCmt">// Binary operation when this struct is the right operand</span>
    <span class="SCmt">// Examples: OneType + myStruct, AnotherType * myStruct</span>
    <span class="SKwd">func</span>(op: <span class="SCst">Swag</span>.<span class="SCst">Operator</span>) <span class="SFct">opBinaryRight</span>(<span class="STpe">me</span>, other: <span class="SCst">OneType</span>)-&gt;<span class="SCst">Struct</span>
    {
        <span class="SLgc">return</span> {<span class="SNum">1</span>, <span class="SNum">2</span>}
    }

    <span class="SKwd">func</span>(op: <span class="SCst">Swag</span>.<span class="SCst">Operator</span>) <span class="SFct">opBinaryRight</span>(<span class="STpe">me</span>, other: <span class="SCst">AnotherType</span>)-&gt;<span class="SCst">Struct</span>
    {
        <span class="SLgc">return</span> {<span class="SNum">1</span>, <span class="SNum">2</span>}
    }

    <span class="SCmt">// A commutative opBinary can also be used when the struct is the right operand.</span>
    <span class="SCmt">// Restrict the operators when a generic opBinary also handles non-commutative ones.</span>
    <span class="SAtr">#[Swag.Commutative(.Add, .Mul)]</span>
    <span class="SKwd">func</span>(op: <span class="SCst">Swag</span>.<span class="SCst">Operator</span>) <span class="SFct">opBinary</span>(<span class="STpe">me</span>, other: <span class="STpe">u32</span>)-&gt;<span class="SCst">Struct</span>
    {
        <span class="SLgc">return</span> {<span class="SNum">1</span>, <span class="SNum">2</span>}
    }

    <span class="SCmt">// Unary operation. 'op' is one of Not, Pos, Neg, BitNot.</span>
    <span class="SCmt">// Unary '-' arrives as 'Neg', so it never collides with the binary 'Sub'.</span>
    <span class="SKwd">func</span>(op: <span class="SCst">Swag</span>.<span class="SCst">Operator</span>) <span class="SFct">opUnary</span>(<span class="STpe">me</span>)-&gt;<span class="SCst">Struct</span>
    {
        <span class="SLgc">return</span> {<span class="SNum">1</span>, <span class="SNum">2</span>}
    }

    <span class="SCmt">// Compound assignment. 'op' is one of AddAssign, SubAssign, MulAssign, DivAssign,</span>
    <span class="SCmt">// ModAssign, BitOrAssign, BitAndAssign, BitXorAssign, ShlAssign, ShrAssign.</span>
    <span class="SKwd">func</span>(op: <span class="SCst">Swag</span>.<span class="SCst">Operator</span>) <span class="SFct">opAssign</span>(<span class="STpe">me</span>, other: <span class="SCst">OneType</span>) {}
    <span class="SKwd">func</span>(op: <span class="SCst">Swag</span>.<span class="SCst">Operator</span>) <span class="SFct">opAssign</span>(<span class="STpe">me</span>, other: <span class="SCst">AnotherType</span>) {}

    <span class="SCmt">// Indexed assignment with operator 'op'. All index parameters must have the same type.</span>
    <span class="SCmt">// When both opIndexAssign and opIndex can write, opIndexAssign is selected.</span>
    <span class="SKwd">func</span>(op: <span class="SCst">Swag</span>.<span class="SCst">Operator</span>) <span class="SFct">opIndexAssign</span>(<span class="STpe">me</span>, index: <span class="SCst">OneType</span>, value: <span class="SCst">OneType</span>) {}
    <span class="SKwd">func</span>(op: <span class="SCst">Swag</span>.<span class="SCst">Operator</span>) <span class="SFct">opIndexAssign</span>(<span class="STpe">me</span>, row: <span class="SCst">OneType</span>, column: <span class="SCst">OneType</span>, value: <span class="SCst">OneType</span>) {}
    <span class="SKwd">func</span>(op: <span class="SCst">Swag</span>.<span class="SCst">Operator</span>) <span class="SFct">opIndexAssign</span>(<span class="STpe">me</span>, index: <span class="SCst">OneType</span>, value: <span class="SCst">AnotherType</span>) {}

    <span class="SCmt">// -------------------------------------------------------------------------</span>
    <span class="SCmt">// Iteration ('for' support)</span>
    <span class="SCmt">// -------------------------------------------------------------------------</span>

    <span class="SCmt">// Called in a 'for' iteration block to iterate over the struct's elements.</span>
    <span class="SCmt">// Multiple versions can be defined by adding a name after 'opVisit'.</span>
    <span class="SAtr">#[Swag.Macro]</span>
    {
        <span class="SKwd">func</span>(ptr: <span class="STpe">bool</span>, back: <span class="STpe">bool</span>) <span class="SFct">opVisit</span>(<span class="STpe">me</span>, stmt: <span class="SItr">#code</span>) {}
        <span class="SKwd">func</span>(ptr: <span class="STpe">bool</span>, back: <span class="STpe">bool</span>) <span class="SFct">opVisitWhatever</span>(<span class="STpe">me</span>, stmt: <span class="SItr">#code</span>) {}
        <span class="SKwd">func</span>(ptr: <span class="STpe">bool</span>, back: <span class="STpe">bool</span>) <span class="SFct">opVisitAnother</span>(<span class="STpe">me</span>, stmt: <span class="SItr">#code</span>) {}
    }
}

</span></div>
<h3 id="_006_006_custom_assignment_swg">Custom Assignment</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Custom_Assignment_Behavior_with__opSet_">Custom Assignment Behavior with <span class="code-inline">opSet</span></h3>
<p>The <span class="code-inline">opSet</span> method in Swag allows you to define custom assignment behaviors for your struct using the <span class="code-inline">=</span> operator. By overloading <span class="code-inline">opSet</span>, you can handle assignments of different types and control how your struct responds.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">struct</span> <span class="SCst">Struct</span>
{
    x, y, z: <span class="STpe">s32</span> = <span class="SNum">666</span>     <span class="SCmt">// Fields with default value 666</span>
}

<span class="SKwd">impl</span> <span class="SCst">Struct</span>
{
    <span class="SCmt">// Overload for 's32'</span>
    <span class="SKwd">mtd</span> <span class="SFct">opSet</span>(value: <span class="STpe">s32</span>)
    {
        <span class="STpe">me</span>.x, <span class="STpe">me</span>.y = value
    }

    <span class="SCmt">// Overload for 'bool'</span>
    <span class="SKwd">mtd</span> <span class="SFct">opSet</span>(value: <span class="STpe">bool</span>)
    {
        <span class="STpe">me</span>.x, <span class="STpe">me</span>.y = value ? <span class="SNum">1</span> : <span class="SNum">0</span>
    }
}

<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> v: <span class="SCst">Struct</span> = <span class="SNum">4</span>'<span class="STpe">s32</span>
    <span class="SItr">@assert</span>(v.x == <span class="SNum">4</span>)
    <span class="SItr">@assert</span>(v.y == <span class="SNum">4</span>)
    <span class="SItr">@assert</span>(v.z == <span class="SNum">666</span>)
    <span class="SKwd">var</span> v1: <span class="SCst">Struct</span> = <span class="SKwd">true</span>
    <span class="SItr">@assert</span>(v1.x == <span class="SNum">1</span>)
    <span class="SItr">@assert</span>(v1.y == <span class="SNum">1</span>)
    v1 = <span class="SKwd">false</span>
    <span class="SItr">@assert</span>(v1.x == <span class="SNum">0</span>)
    <span class="SItr">@assert</span>(v1.y == <span class="SNum">0</span>)
}

</span></div>
<h3 id="Optimizing_Initialization_with__Swag_FullInit_">Optimizing Initialization with <span class="code-inline">Swag.FullInit</span></h3>
<p>When <span class="code-inline">opSet</span> completely initializes the struct, mark it with <span class="code-inline">#[Swag.FullInit]</span>. This avoids default initialization before assignment for better performance.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">impl</span> <span class="SCst">Struct</span>
{
    <span class="SAtr">#[Swag.FullInit]</span>
    <span class="SKwd">mtd</span> <span class="SFct">opSet</span>(value: <span class="STpe">u64</span>)
    {
        <span class="STpe">me</span>.x, <span class="STpe">me</span>.y, <span class="STpe">me</span>.z = <span class="SKwd">cast</span>(<span class="STpe">s32</span>) value
    }

    <span class="SAtr">#[Swag.Implicit]</span>
    <span class="SKwd">mtd</span> <span class="SFct">opSet</span>(value: <span class="STpe">u16</span>)
    {
        <span class="STpe">me</span>.x, <span class="STpe">me</span>.y = <span class="SKwd">cast</span>(<span class="STpe">s32</span>) value
    }
}

<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> v: <span class="SCst">Struct</span> = <span class="SNum">2</span>'<span class="STpe">u64</span>
    <span class="SItr">@assert</span>(v.x == <span class="SNum">2</span>)
    <span class="SItr">@assert</span>(v.y == <span class="SNum">2</span>)
    <span class="SItr">@assert</span>(v.z == <span class="SNum">2</span>)
}

</span></div>
<h3 id="Handling_Function_Arguments_and_Automatic_Conversion">Handling Function Arguments and Automatic Conversion</h3>
<p>Function arguments are not automatically converted through <span class="code-inline">opSet</span> unless <span class="code-inline">Swag.Implicit</span> is used. Otherwise, an explicit cast is required.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">func</span> <span class="SFct">takesExplicit</span>(v: <span class="SCst">Struct</span>)
    {
        <span class="SItr">@assert</span>(v.x == <span class="SNum">5</span>)
        <span class="SItr">@assert</span>(v.y == <span class="SNum">5</span>)
        <span class="SItr">@assert</span>(v.z == <span class="SNum">666</span>)
    }

    <span class="SKwd">func</span> <span class="SFct">takesImplicit</span>(v: <span class="SCst">Struct</span>)
    {
        <span class="SItr">@assert</span>(v.x == <span class="SNum">5</span>)
        <span class="SItr">@assert</span>(v.y == <span class="SNum">5</span>)
        <span class="SItr">@assert</span>(v.z == <span class="SNum">666</span>)
    }

    <span class="SCmt">// Explicit cast triggers 'opSet(s32)'</span>
    <span class="SFct">takesExplicit</span>(<span class="SKwd">cast</span>(<span class="SCst">Struct</span>) <span class="SNum">5</span>'<span class="STpe">s32</span>)

    <span class="SCmt">// Implicit conversion via 'opSet(u16)'</span>
    <span class="SFct">takesImplicit</span>(<span class="SNum">5</span>'<span class="STpe">u16</span>)
}

</span></div>
<h3 id="Using__opSet__in_Constant_Expressions">Using <span class="code-inline">opSet</span> in Constant Expressions</h3>
<p>To allow compile-time initialization through <span class="code-inline">opSet</span>, mark it with <span class="code-inline">#[Swag.ConstExpr]</span>.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">struct</span> <span class="SCst">Vector2</span>
{
    x, y: <span class="STpe">f32</span>
}

<span class="SKwd">impl</span> <span class="SCst">Vector2</span>
{
    <span class="SAtr">#[Swag.ConstExpr]</span>
    <span class="SKwd">mtd</span> <span class="SFct">opSet</span>(one: <span class="STpe">f32</span>)
    {
        <span class="STpe">me</span>.x, <span class="STpe">me</span>.y = one
    }
}

<span class="SKwd">const</span> <span class="SCst">One</span>: <span class="SCst">Vector2</span> = <span class="SNum">1.0</span>
<span class="SCmp">#assert</span>(<span class="SCst">One</span>.x == <span class="SNum">1.0</span>)
<span class="SCmp">#assert</span>(<span class="SCst">One</span>.y == <span class="SNum">1.0</span>)

</span></div>
<h3 id="_006_007_custom_loop_swg">Custom Loop</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

<span class="SKwd">struct</span> <span class="SCst">MyStruct</span> {}

</span></div>
<h3 id="Implementing__opCount__for_Iteration">Implementing <span class="code-inline">opCount</span> for Iteration</h3>
<p>The <span class="code-inline">opCount</span> method in Swag specifies how many iterations a loop performs when looping over a struct instance. By defining it, you make the struct act like an iterable object with a controlled length.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">impl</span> <span class="SCst">MyStruct</span>
{
    <span class="SCmt">// Return the number of iterations for loops using this struct</span>
    <span class="SKwd">mtd</span> <span class="SFct">opCount</span>() =&gt; <span class="SNum">4</span>'<span class="STpe">u64</span>
}

</span></div>
<p>With <span class="code-inline">opCount</span> defined, an instance of <span class="code-inline">MyStruct</span> can be used in loops just like arrays or other iterable types. The loop executes the number of times returned by <span class="code-inline">opCount</span>.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> v = <span class="SCst">MyStruct</span>{}
    <span class="SItr">@assert</span>(<span class="SItr">@countof</span>(v) == <span class="SNum">4</span>)
    <span class="SKwd">var</span> cpt = <span class="SNum">0</span>
    <span class="SLgc">for</span> v <span class="SLgc">do</span>
        cpt += <span class="SNum">1</span>
    <span class="SItr">@assert</span>(cpt == <span class="SNum">4</span>)
}

</span></div>
<h3 id="_006_008_custom_iteration_swg">Custom Iteration</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

<span class="SKwd">struct</span> <span class="SCst">MyStruct</span>
{
    x: <span class="STpe">s32</span> = <span class="SNum">10</span>
    y: <span class="STpe">s32</span> = <span class="SNum">20</span>
    z: <span class="STpe">s32</span> = <span class="SNum">30</span>
}

</span></div>
<h3 id="The__opVisit__Iteration_Hook">The <span class="code-inline">opVisit</span> Iteration Hook</h3>
<p><span class="code-inline">opVisit</span> is a flexible macro for iterating over elements of a struct or any data it owns (dynamic arrays, buffers, object graphs). The <span class="code-inline">#[Swag.Macro]</span> attribute is mandatory.</p>
<p><span class="code-inline">opVisit</span> is generic over two compile-time booleans:</p>
<ul>
<li><span class="code-inline">ptr</span>: if true, elements are visited by pointer (address).</li>
<li><span class="code-inline">back</span>: if true, elements are visited in reverse order.</li>
</ul>
<p>The code block declares its parameters like a function, with <span class="code-inline">func</span> replaced by <span class="code-inline">#code</span>. The parameter names (<span class="code-inline">item</span> and <span class="code-inline">index</span> here) are the contract: they are the names the caller sees by default, and the names bound by <span class="code-inline">#inject</span>.</p>
<p>Each <span class="code-inline">#inject</span> clones the caller's code: when a value is selected at runtime, compute it into a local first and keep a single <span class="code-inline">#inject</span>, instead of one <span class="code-inline">#inject</span> per branch.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">impl</span> <span class="SCst">MyStruct</span>
{
    <span class="SAtr">#[Swag.Macro]</span>
    <span class="SKwd">func</span>(ptr: <span class="STpe">bool</span>, back: <span class="STpe">bool</span>) <span class="SFct">opVisit</span>(<span class="STpe">me</span>, stmt: <span class="SItr">#code</span>(item: <span class="STpe">s32</span>, index: <span class="STpe">u64</span>))
    {
        <span class="SCmp">#static</span> <span class="SLgc">if</span> ptr <span class="SLgc">do</span>
            <span class="SCmp">#error</span>(<span class="SStr">"Visiting by pointer is not supported in this example."</span>)

        <span class="SCmp">#static</span> <span class="SLgc">if</span> back <span class="SLgc">do</span>
            <span class="SCmp">#error</span>(<span class="SStr">"Reverse visiting is not supported in this example."</span>)

        <span class="SCmt">// Visit fields x, y, z in declaration order</span>
        <span class="SLgc">for</span> [idx] <span class="SLgc">in</span> <span class="SNum">3</span>
        {
            <span class="SKwd">var</span> visitItem: <span class="STpe">s32</span> = <span class="SKwd">undefined</span>
            <span class="SLgc">switch</span> idx
            {
            <span class="SLgc">case</span> <span class="SNum">0</span>:  visitItem = <span class="STpe">me</span>.x
            <span class="SLgc">case</span> <span class="SNum">1</span>:  visitItem = <span class="STpe">me</span>.y
            <span class="SLgc">default</span>: visitItem = <span class="STpe">me</span>.z
            }

            <span class="SCmp">#inject</span>(stmt, item = visitItem, index = <span class="SItr">@index</span>)
        }
    }
}

</span></div>
<h3 id="Iterating_Over_Struct_Fields">Iterating Over Struct Fields</h3>
<p>Example usage of <span class="code-inline">opVisit</span> to traverse fields of a struct. A plain name binds the first block parameter, and a bracketed name binds the second one. As with built-in collections, <span class="code-inline">for [i] in value</span> binds only that second parameter.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> myStruct = <span class="SCst">MyStruct</span>{}
    <span class="SKwd">var</span> cpt      = <span class="SNum">0</span>

    <span class="SLgc">for</span> v, [i] <span class="SLgc">in</span> myStruct
    {
        <span class="SLgc">switch</span> i
        {
        <span class="SLgc">case</span> <span class="SNum">0</span>: <span class="SItr">@assert</span>(v == <span class="SNum">10</span>)
        <span class="SLgc">case</span> <span class="SNum">1</span>: <span class="SItr">@assert</span>(v == <span class="SNum">20</span>)
        <span class="SLgc">case</span> <span class="SNum">2</span>: <span class="SItr">@assert</span>(v == <span class="SNum">30</span>)
        }

        cpt += <span class="SNum">1</span>
    }

    <span class="SItr">@assert</span>(cpt == <span class="SNum">3</span>)
}

<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> myStruct = <span class="SCst">MyStruct</span>{}
    <span class="SKwd">var</span> sum: <span class="STpe">u64</span>

    <span class="SLgc">for</span> [i] <span class="SLgc">in</span> myStruct <span class="SLgc">do</span>
        sum += i

    <span class="SItr">@assert</span>(sum == <span class="SNum">3</span>)
}

</span></div>
<h3 id="Extending__opVisit___Reverse_Order_Iteration">Extending <span class="code-inline">opVisit</span>: Reverse Order Iteration</h3>
<p>An alternative macro that visits fields in reverse order.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">impl</span> <span class="SCst">MyStruct</span>
{
    <span class="SAtr">#[Swag.Macro]</span>
    <span class="SKwd">mtd</span>(ptr: <span class="STpe">bool</span>, back: <span class="STpe">bool</span>) <span class="SFct">opVisitReverse</span>(stmt: <span class="SItr">#code</span>(item: <span class="STpe">s32</span>, index: <span class="STpe">u64</span>))
    {
        <span class="SLgc">for</span> [idx] <span class="SLgc">in</span> <span class="SNum">3</span>
        {
            <span class="SKwd">var</span> visitItem: <span class="STpe">s32</span> = <span class="SKwd">undefined</span>
            <span class="SLgc">switch</span> idx
            {
            <span class="SLgc">case</span> <span class="SNum">0</span>:  visitItem = <span class="STpe">me</span>.z
            <span class="SLgc">case</span> <span class="SNum">1</span>:  visitItem = <span class="STpe">me</span>.y
            <span class="SLgc">default</span>: visitItem = <span class="STpe">me</span>.x
            }

            <span class="SCmp">#inject</span>(stmt, item = visitItem, index = <span class="SItr">@index</span>)
        }
    }
}

</span></div>
<h3 id="Reverse_Order_Iteration">Reverse Order Iteration</h3>
<p>Using <span class="code-inline">opVisitReverse</span> to iterate fields from last to first.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> myStruct = <span class="SCst">MyStruct</span>{}
    <span class="SKwd">var</span> cpt      = <span class="SNum">0</span>

    <span class="SLgc">for</span> <span class="SInv">#Reverse</span> v, [i] <span class="SLgc">in</span> myStruct
    {
        <span class="SLgc">switch</span> i
        {
        <span class="SLgc">case</span> <span class="SNum">0</span>: <span class="SItr">@assert</span>(v == <span class="SNum">30</span>)
        <span class="SLgc">case</span> <span class="SNum">1</span>: <span class="SItr">@assert</span>(v == <span class="SNum">20</span>)
        <span class="SLgc">case</span> <span class="SNum">2</span>: <span class="SItr">@assert</span>(v == <span class="SNum">10</span>)
        }

        cpt += <span class="SNum">1</span>
    }

    <span class="SItr">@assert</span>(cpt == <span class="SNum">3</span>)
}

</span></div>
<h3 id="Visiting_Elements_in_Dynamic_Arrays">Visiting Elements in Dynamic Arrays</h3>
<p>Beyond fields, <span class="code-inline">opVisit</span> can target owned collections such as dynamic arrays.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">struct</span> <span class="SCst">SliceStruct</span>
{
    buffer: [?] <span class="STpe">s32</span> = [<span class="SNum">1</span>, <span class="SNum">2</span>, <span class="SNum">3</span>, <span class="SNum">4</span>, <span class="SNum">5</span>]
}

</span></div>
<h3 id="Custom__opVisit__for_Dynamic_Arrays">Custom <span class="code-inline">opVisit</span> for Dynamic Arrays</h3>
<p>Iterate over <span class="code-inline">buffer</span> elements instead of struct fields. When the element type depends on compile-time parameters (<span class="code-inline">ptr</span> here), leave the block parameter untyped and pick the binding expression per branch.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">impl</span> <span class="SCst">SliceStruct</span>
{
    <span class="SAtr">#[Swag.Macro]</span>
    <span class="SKwd">func</span>(ptr: <span class="STpe">bool</span>, back: <span class="STpe">bool</span>) <span class="SFct">opVisit</span>(<span class="STpe">me</span>, stmt: <span class="SItr">#code</span>(item, index: <span class="STpe">u64</span>))
    {
        <span class="SCmp">#static</span> <span class="SLgc">if</span> back <span class="SLgc">do</span>
            <span class="SCmp">#error</span>(<span class="SStr">"Reverse visiting is not supported for this slice example."</span>)

        <span class="SLgc">for</span> [idx] <span class="SLgc">in</span> <span class="SItr">@countof</span>(<span class="STpe">me</span>.buffer)
        {
            <span class="SCmp">#static</span> <span class="SLgc">if</span> ptr <span class="SLgc">do</span>
                <span class="SCmp">#inject</span>(stmt, item = <span class="SKwd">cast</span>(&amp;<span class="STpe">s32</span>) &amp;<span class="STpe">me</span>.buffer[idx], index = <span class="SItr">@index</span>)
            <span class="SLgc">else</span> <span class="SLgc">do</span>
                <span class="SCmp">#inject</span>(stmt, item = <span class="STpe">me</span>.buffer[idx], index = <span class="SItr">@index</span>)
        }
    }
}

</span></div>
<h3 id="Iterating_Over_a_Dynamic_Array">Iterating Over a Dynamic Array</h3>
<p>Sum elements of a slice via <span class="code-inline">opVisit</span>.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> arrStruct = <span class="SCst">SliceStruct</span>{}
    <span class="SKwd">var</span> sum       = <span class="SNum">0</span>

    <span class="SLgc">for</span> v, [i] <span class="SLgc">in</span> arrStruct <span class="SLgc">do</span>
        sum += v

    <span class="SItr">@assert</span>(sum == <span class="SNum">1</span> + <span class="SNum">2</span> + <span class="SNum">3</span> + <span class="SNum">4</span> + <span class="SNum">5</span>)
}

</span></div>
<h3 id="Visiting_by_Pointer">Visiting by Pointer</h3>
<p>'ptr == true' lets custom iteration expose elements by reference so the loop body can update the underlying storage.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> arrStruct = <span class="SCst">SliceStruct</span>{}

    <span class="SLgc">for</span> &amp;v, [i] <span class="SLgc">in</span> arrStruct <span class="SLgc">do</span>
        v += <span class="SKwd">cast</span>(<span class="STpe">s32</span>) i

    <span class="SItr">@assert</span>(arrStruct.buffer[<span class="SNum">0</span>] == <span class="SNum">1</span>)
    <span class="SItr">@assert</span>(arrStruct.buffer[<span class="SNum">1</span>] == <span class="SNum">3</span>)
    <span class="SItr">@assert</span>(arrStruct.buffer[<span class="SNum">2</span>] == <span class="SNum">5</span>)
    <span class="SItr">@assert</span>(arrStruct.buffer[<span class="SNum">3</span>] == <span class="SNum">7</span>)
    <span class="SItr">@assert</span>(arrStruct.buffer[<span class="SNum">4</span>] == <span class="SNum">9</span>)
}

</span></div>
<h3 id="Named_Variants_of__opVisit_">Named Variants of <span class="code-inline">opVisit</span></h3>
<p>A specialization such as 'for #Pairs ...' resolves to <span class="code-inline">opVisitPairs</span>. This is useful when a type wants to expose multiple traversal strategies.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">struct</span> <span class="SCst">WindowStruct</span>
{
    values: [<span class="SNum">4</span>] <span class="STpe">s32</span> = [<span class="SNum">2</span>, <span class="SNum">4</span>, <span class="SNum">6</span>, <span class="SNum">8</span>]
}

<span class="SKwd">impl</span> <span class="SCst">WindowStruct</span>
{
    <span class="SAtr">#[Swag.Macro]</span>
    <span class="SKwd">mtd</span>(ptr: <span class="STpe">bool</span>, back: <span class="STpe">bool</span>) <span class="SKwd">const</span> <span class="SFct">opVisitPairs</span>(stmt: <span class="SItr">#code</span>(left: <span class="STpe">s32</span>, right: <span class="STpe">s32</span>))
    {
        <span class="SCmp">#static</span> <span class="SLgc">if</span> ptr <span class="SLgc">do</span>
            <span class="SCmp">#error</span>(<span class="SStr">"WindowStruct does not expose pointer iteration for pair visits."</span>)

        <span class="SLgc">for</span> [idx] <span class="SLgc">in</span> <span class="SNum">3</span>
        {
            <span class="SCmp">#inject</span>(stmt, left = <span class="STpe">me</span>.values[idx], right = <span class="STpe">me</span>.values[idx + <span class="SNum">1</span>])
        }
    }
}

</span></div>
<h3 id="Iterating_Over_Adjacent_Pairs">Iterating Over Adjacent Pairs</h3>
<p>Named variants can expose completely custom block parameters; <span class="code-inline">@index</span> still tracks the iteration ordinal.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> windows = <span class="SCst">WindowStruct</span>{}
    <span class="SKwd">var</span> code    = <span class="SNum">0</span>
    <span class="SKwd">var</span> ordinals: <span class="STpe">u64</span>

    <span class="SLgc">for</span> <span class="SInv">#Pairs</span> left, [right] <span class="SLgc">in</span> windows
    {
        code     = code * <span class="SNum">100</span> + left * <span class="SNum">10</span> + right
        ordinals += <span class="SItr">@index</span>
    }

    <span class="SItr">@assert</span>(code == <span class="SNum">244668</span>)
    <span class="SItr">@assert</span>(ordinals == <span class="SNum">3</span>)
}

</span></div>
<h3 id="_006_009_custom_copy_and_move_swg">Custom Copy and Move</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<p>Swag supports both copy and move semantics for structures. In this example, we demonstrate these concepts using a <span class="code-inline">Vector3</span> struct. Although a <span class="code-inline">Vector3</span> typically wouldn't require move semantics (no heap allocation), this illustrates how these features can be implemented and used in Swag.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">struct</span> <span class="SCst">Vector3</span>
{
    x, y, z: <span class="STpe">s32</span> = <span class="SNum">666</span>
}

<span class="SKwd">impl</span> <span class="SCst">Vector3</span>
{
    <span class="SCmt">// Called after a copy; customize post-copy behavior here.</span>
    <span class="SKwd">mtd</span> <span class="SFct">opPostCopy</span>()
    {
        .x, .y, .z += <span class="SNum">1</span>
    }

    <span class="SCmt">// Called after a move; customize post-move behavior here.</span>
    <span class="SKwd">mtd</span> <span class="SFct">opPostMove</span>()
    {
        .x, .y, .z += <span class="SNum">2</span>
    }

    <span class="SCmt">// Called before destruction; place cleanup here if needed.</span>
    <span class="SKwd">mtd</span> <span class="SFct">opDrop</span>() {}
}

<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> a = <span class="SCst">Vector3</span>{}                  <span class="SCmt">// Default init.</span>
    <span class="SKwd">var</span> b = <span class="SCst">Vector3</span>{<span class="SNum">100</span>, <span class="SNum">200</span>, <span class="SNum">300</span>}     <span class="SCmt">// Custom init.</span>

    <span class="SCmt">// Copy semantics: drop 'a' (if needed), copy 'b' to 'a', then call 'opPostCopy' on 'a'.</span>
    a = b
    <span class="SItr">@assert</span>(a.x == <span class="SNum">101</span>)
    <span class="SItr">@assert</span>(a.y == <span class="SNum">201</span>)
    <span class="SItr">@assert</span>(a.z == <span class="SNum">301</span>)

    <span class="SCmt">// Move semantics with '#move': drop 'a' (if needed), move 'b' to 'a', then call 'opPostMove' on 'a'.</span>
    <span class="SCmt">// With 'opDrop' present, 'b' is reinitialized to defaults (666).</span>
    a = <span class="SItr">#move</span> b
    <span class="SItr">@assert</span>(a.x == <span class="SNum">102</span>)
    <span class="SItr">@assert</span>(a.y == <span class="SNum">202</span>)
    <span class="SItr">@assert</span>(a.z == <span class="SNum">302</span>)
    <span class="SItr">@assert</span>(b.x == <span class="SNum">666</span>)

    <span class="SCmt">// '#nodrop' skips the initial drop of 'a'.</span>
    a = <span class="SItr">#nodrop</span> b           <span class="SCmt">// Copy without dropping 'a' first.</span>
    a = <span class="SItr">#nodrop</span> <span class="SItr">#move</span> b     <span class="SCmt">// Move without dropping 'a' first.</span>

    <span class="SCmt">// '#relocate' is the raw relocation used by container internals: the target is treated</span>
    <span class="SCmt">// as uninitialized (no drop) and the source is abandoned (no reinitialization). Use with care.</span>
    a = <span class="SItr">#relocate</span> b
}

</span></div>
<h3 id="Drop_Elision">Drop Elision</h3>
<p>When the source of a <span class="code-inline">#move</span> is a plain local that is provably never used again — no read or write after the move, no taken address, no capture, and a move that always executes when its scope exits — the compiler elides both the reset of the source and its scope-exit drop: <span class="code-inline">opDrop</span> is then NOT called on the reset value. A program can therefore not rely on counting the drops of fully consumed locals. Any use after the move (or any use the compiler cannot prove harmless) keeps the documented reset-then-drop behavior.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="Lifecycle_Safety">Lifecycle Safety</h3>
<p>Reading a value abandoned by <span class="code-inline">#relocate</span> — or by <span class="code-inline">#move</span> when the type has no <span class="code-inline">opDrop</span>, which leaves the source unreset — reads stale bits. Under the <span class="code-inline">Swag.SafetyWhat.Lifecycle</span> safety guard (part of <span class="code-inline">All</span>, so enabled by default in debug configurations), the compiler reports proven reads of moved-from locals at compile time, and poisons abandoned or dropped storage with <span class="code-inline">0xDD</span> bytes at runtime so hidden violations fail deterministically instead of silently reading stale data. A <span class="code-inline">#move</span> of a type with <span class="code-inline">opDrop</span> is not concerned: the source is reset to its defaults, which is defined behavior.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="Move_Semantics_in_Functions">Move Semantics in Functions</h3>
<p>Move semantics can be expressed in function parameters by prefixing the parameter type with <span class="code-inline">#move</span>. At the call site, prefix the argument with <span class="code-inline">#move</span> to pass it as a move reference.</p>
<p>A <span class="code-inline">#move</span> parameter also accepts a plain (copyable) value: the compiler then materializes a temporary copy at the call site and passes it as the move reference. A single <span class="code-inline">#move</span> function therefore serves both call styles — including through lambdas, function pointers and interface methods — at the price of one extra copy on the copy path. This works for structs, for plain scalar values (integers, floats, bool, rune, enums), and for untyped literals alike.</p>
<p>Conversely, an explicit <span class="code-inline">#move</span> argument is always honored. Passed to a <span class="code-inline">#move</span> parameter, it is the zero-cost transfer above. Passed to a BY-VALUE parameter, the source is moved into a call-site temporary that the callee borrows: the caller drops the temporary right after the call, and the source is consumed. Passed to a reference or pointer parameter, it is a compile-time error — the transfer would be silently ignored. On by-value scalars, <span class="code-inline">#move</span> is accepted and equivalent to a plain pass.</p>
<p>A named function can avoid that extra copy by declaring the parameter with <span class="code-inline">#fwd</span> instead: the compiler emits two overloads, a copy variant (the parameter behaves like a plain value) and a move variant (the parameter behaves like <span class="code-inline">#move</span>). Inside the body, <span class="code-inline">#fwd</span> forwards the parameter with the mode of the selected variant. Calls without <span class="code-inline">#move</span> then pick the dedicated copy variant, with no temporary. With several <span class="code-inline">#fwd</span> parameters, a mixed call picks whichever variant matches best; the <span class="code-inline">#move</span> arguments are honored either way — through the move variant's parameter, or through a by-value move into the copy variant's parameter.</p>
<p>If the type is not copyable (marked with <span class="code-inline">#[Swag.NoCopy]</span>), the copy paths are automatically discarded at overload resolution: only a <span class="code-inline">#move</span> call is accepted.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SCmt">// One declaration, two variants: 'assign(&amp;v, x)' copies, 'assign(&amp;v, #move x)' moves.</span>
    <span class="SKwd">func</span> <span class="SFct">assign</span>(assignTo: &amp;<span class="SCst">Vector3</span>, from: <span class="SItr">#fwd</span> <span class="SCst">Vector3</span>)
    {
        assignTo = <span class="SItr">#fwd</span> from
    }

    <span class="SKwd">var</span> a = <span class="SCst">Vector3</span>{<span class="SNum">1</span>, <span class="SNum">2</span>, <span class="SNum">3</span>}
    <span class="SKwd">var</span> b: <span class="SCst">Vector3</span>

    <span class="SCmt">// Copy path.</span>
    <span class="SFct">assign</span>(&amp;b, a)
    <span class="SItr">@assert</span>(b.x == <span class="SNum">2</span> <span class="SLgc">and</span> b.y == <span class="SNum">3</span> <span class="SLgc">and</span> b.z == <span class="SNum">4</span>)     <span class="SCmt">// +1 via 'opPostCopy'.</span>
    <span class="SItr">@assert</span>(a.x == <span class="SNum">1</span> <span class="SLgc">and</span> a.y == <span class="SNum">2</span> <span class="SLgc">and</span> a.z == <span class="SNum">3</span>)     <span class="SCmt">// 'a' unchanged.</span>

    <span class="SCmt">// Move path: '#move' passes 'a' as a move reference.</span>
    <span class="SFct">assign</span>(&amp;b, <span class="SItr">#move</span> a)
    <span class="SItr">@assert</span>(b.x == <span class="SNum">3</span> <span class="SLgc">and</span> b.y == <span class="SNum">4</span> <span class="SLgc">and</span> b.z == <span class="SNum">5</span>)           <span class="SCmt">// +2 via 'opPostMove'.</span>
    <span class="SItr">@assert</span>(a.x == <span class="SNum">666</span> <span class="SLgc">and</span> a.y == <span class="SNum">666</span> <span class="SLgc">and</span> a.z == <span class="SNum">666</span>)     <span class="SCmt">// 'a' reset to defaults after move.</span>
}

<span class="SFct">#test</span>
{
    <span class="SCmt">// A single '#move' function also accepts both call styles: a plain argument is</span>
    <span class="SCmt">// copied into a call-site temporary, then moved from it.</span>
    <span class="SKwd">func</span> <span class="SFct">assign</span>(assignTo: &amp;<span class="SCst">Vector3</span>, from: <span class="SItr">#move</span> <span class="SCst">Vector3</span>)
    {
        assignTo = <span class="SItr">#move</span> from
    }

    <span class="SKwd">var</span> a = <span class="SCst">Vector3</span>{<span class="SNum">1</span>, <span class="SNum">2</span>, <span class="SNum">3</span>}
    <span class="SKwd">var</span> b: <span class="SCst">Vector3</span>

    <span class="SCmt">// Copy call style: 'a' is copied into a temporary (+1), the temporary is moved (+2).</span>
    <span class="SFct">assign</span>(&amp;b, a)
    <span class="SItr">@assert</span>(b.x == <span class="SNum">4</span> <span class="SLgc">and</span> b.y == <span class="SNum">5</span> <span class="SLgc">and</span> b.z == <span class="SNum">6</span>)
    <span class="SItr">@assert</span>(a.x == <span class="SNum">1</span> <span class="SLgc">and</span> a.y == <span class="SNum">2</span> <span class="SLgc">and</span> a.z == <span class="SNum">3</span>)     <span class="SCmt">// 'a' unchanged.</span>

    <span class="SCmt">// Move call style: zero extra cost.</span>
    <span class="SFct">assign</span>(&amp;b, <span class="SItr">#move</span> a)
    <span class="SItr">@assert</span>(b.x == <span class="SNum">3</span> <span class="SLgc">and</span> b.y == <span class="SNum">4</span> <span class="SLgc">and</span> b.z == <span class="SNum">5</span>)
    <span class="SItr">@assert</span>(a.x == <span class="SNum">666</span> <span class="SLgc">and</span> a.y == <span class="SNum">666</span> <span class="SLgc">and</span> a.z == <span class="SNum">666</span>)
}

</span></div>
<h3 id="_006_010_custom_literals_swg">Custom Literals</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="User-Defined_Literals">User-Defined Literals</h3>
<p>User-defined literals extend literal meaning so custom types can be initialized directly with unit-like suffixes (e.g., <span class="code-inline">4</span>ms'). This example defines a <span class="code-inline">Duration</span> type that stores seconds and accepts seconds, milliseconds, minutes, and hours.</p>
<h3 id="Literal_Suffixes">Literal Suffixes</h3>
<p>A literal suffix immediately follows a numeric literal to indicate a unit or type, e.g., <span class="code-inline">4'ms</span> means 4 milliseconds.</p>
<p>To support user-defined literals, provide: 1) a type (e.g., <span class="code-inline">Duration</span>), and 2) methods to convert the numeric value according to the suffix.</p>
<div class="code-block"><span class="SCde">
<span class="SCmt">// Represents a delay, expressed in seconds.</span>
<span class="SKwd">struct</span> <span class="SCst">Duration</span>
{
    timeInSeconds: <span class="STpe">f32</span>
}

</span></div>
<p>Use the operator overload hook <span class="code-inline">opSetLiteral</span> to convert a value plus suffix.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">impl</span> <span class="SCst">Duration</span>
{
    <span class="SCmt">// Handle literals like '5's', '500'ms', '2'min', '1'h'</span>
    <span class="SAtr">#[Swag.ConstExpr, Swag.Implicit, Swag.Inline]</span>
    <span class="SKwd">mtd</span>(suffix: <span class="STpe">string</span>) <span class="SFct">opSetLiteral</span>(value: <span class="STpe">s32</span>)
    {
        <span class="SCmp">#static</span> <span class="SLgc">switch</span> suffix
        {
        <span class="SLgc">case</span> <span class="SStr">"s"</span>:   <span class="STpe">me</span>.timeInSeconds = value
        <span class="SLgc">case</span> <span class="SStr">"ms"</span>:  <span class="STpe">me</span>.timeInSeconds = value / <span class="SNum">1000.0</span>
        <span class="SLgc">case</span> <span class="SStr">"min"</span>: <span class="STpe">me</span>.timeInSeconds = value * <span class="SNum">60.0</span>
        <span class="SLgc">case</span> <span class="SStr">"h"</span>:   <span class="STpe">me</span>.timeInSeconds = value * <span class="SNum">3600.0</span>
        <span class="SLgc">default</span>:    <span class="SCmp">#error</span>(<span class="SStr">"invalid duration literal suffix '"</span> ++ suffix ++ <span class="SStr">"'"</span>)
        }
    }
}

</span></div>
<p>You can then place the suffix right after the numeric literal when the type is <span class="code-inline">Duration</span>.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">func</span> <span class="SFct">toto</span>(x: <span class="SCst">Duration</span>) {}

<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> delaySeconds:      <span class="SCst">Duration</span> = <span class="SNum">5</span>'s
    <span class="SKwd">let</span> delayMilliseconds: <span class="SCst">Duration</span> = <span class="SNum">500</span>'ms
    <span class="SKwd">let</span> delayMinutes:      <span class="SCst">Duration</span> = <span class="SNum">2</span>'min
    <span class="SKwd">let</span> delayHours:        <span class="SCst">Duration</span> = <span class="SNum">1</span>'h

    <span class="SItr">@assert</span>(delaySeconds.timeInSeconds == <span class="SNum">5.0</span>)
    <span class="SItr">@assert</span>(delayMilliseconds.timeInSeconds == <span class="SNum">0.5</span>)
    <span class="SItr">@assert</span>(delayMinutes.timeInSeconds == <span class="SNum">120.0</span>)
    <span class="SItr">@assert</span>(delayHours.timeInSeconds == <span class="SNum">3600.0</span>)

    <span class="SCmt">// Use the 'Duration' type in functions</span>
    <span class="SFct">toto</span>(<span class="SNum">5</span>'ms)
    <span class="SFct">toto</span>(<span class="SNum">1</span>'h)
}

</span></div>
<h3 id="_006_011_interface_swg">Interface</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<p>Interfaces in Swag are virtual tables (lists of function pointers) that can be associated with a struct.</p>
<p>Unlike C++, the virtual table is not embedded in the struct; it is a separate object. This lets you implement an interface for a struct without changing the struct.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">struct</span> <span class="SCst">Point2</span>
{
    x, y: <span class="STpe">f32</span>
}

<span class="SKwd">struct</span> <span class="SCst">Point3</span>
{
    x, y, z: <span class="STpe">f32</span>
}

</span></div>
<h3 id="Interface_Declaration">Interface Declaration</h3>
<p>Declare interface <span class="code-inline">IReset</span> with two functions <span class="code-inline">set</span> and <span class="code-inline">reset</span>.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">interface</span> <span class="SCst">IReset</span>
{
    <span class="SCmt">// First parameter must be 'me' when using 'func'</span>
    <span class="SKwd">mtd</span> <span class="SFct">set</span>(val: <span class="STpe">f32</span>)

    <span class="SCmt">// 'mtd' avoids specifying 'me'</span>
    <span class="SKwd">mtd</span> <span class="SFct">reset</span>()
}

</span></div>
<h3 id="Implementing_an_Interface">Implementing an Interface</h3>
<p>Implement interface <span class="code-inline">IReset</span> for <span class="code-inline">Point2</span>.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">impl</span> <span class="SCst">IReset</span> <span class="SLgc">for</span> <span class="SCst">Point2</span>
{
    <span class="SCmt">// Mark with 'impl' to implement an interface function</span>
    <span class="SKwd">mtd</span> <span class="SKwd">impl</span> <span class="SFct">set</span>(val: <span class="STpe">f32</span>)
    {
        <span class="STpe">me</span>.x = val
        <span class="STpe">me</span>.y = val + <span class="SNum">1</span>
    }

    <span class="SKwd">mtd</span> <span class="SKwd">impl</span> <span class="SFct">reset</span>()
    {
        <span class="STpe">me</span>.x, <span class="STpe">me</span>.y = <span class="SNum">0</span>
    }

    <span class="SCmt">// Regular methods may also appear in this 'impl'</span>
    <span class="SKwd">mtd</span> <span class="SFct">myOtherMethod</span>() {}
}

</span></div>
<h3 id="Implementing_the_Interface_for_Another_Struct">Implementing the Interface for Another Struct</h3>
<p>Implement <span class="code-inline">IReset</span> for <span class="code-inline">Point3</span>.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">impl</span> <span class="SCst">IReset</span> <span class="SLgc">for</span> <span class="SCst">Point3</span>
{
    <span class="SKwd">mtd</span> <span class="SKwd">impl</span> <span class="SFct">set</span>(val: <span class="STpe">f32</span>)
    {
        <span class="STpe">me</span>.x = val
        <span class="STpe">me</span>.y = val + <span class="SNum">1</span>
        <span class="STpe">me</span>.z = val + <span class="SNum">2</span>
    }

    <span class="SKwd">mtd</span> <span class="SKwd">impl</span> <span class="SFct">reset</span>()
    {
        <span class="STpe">me</span>.x, <span class="STpe">me</span>.y, <span class="STpe">me</span>.z = <span class="SNum">0</span>
    }
}

</span></div>
<h3 id="Using_the_Interface">Using the Interface</h3>
<p>Cast to the interface and call its methods.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> pt2: <span class="SCst">Point2</span>
    <span class="SKwd">var</span> pt3: <span class="SCst">Point3</span>
    <span class="SKwd">var</span> itf = <span class="SKwd">cast</span>(<span class="SCst">IReset</span>) pt2
    itf.<span class="SFct">set</span>(<span class="SNum">10</span>)
    <span class="SItr">@assert</span>(pt2.x == <span class="SNum">10</span>)
    <span class="SItr">@assert</span>(pt2.y == <span class="SNum">11</span>)
    itf = <span class="SKwd">cast</span>(<span class="SCst">IReset</span>) pt3
    itf.<span class="SFct">set</span>(<span class="SNum">10</span>)
    <span class="SItr">@assert</span>(pt3.x == <span class="SNum">10</span>)
    <span class="SItr">@assert</span>(pt3.y == <span class="SNum">11</span>)
    <span class="SItr">@assert</span>(pt3.z == <span class="SNum">12</span>)
    itf.<span class="SFct">reset</span>()
    <span class="SItr">@assert</span>(pt3.x == <span class="SNum">0</span> <span class="SLgc">and</span> pt3.y == <span class="SNum">0</span> <span class="SLgc">and</span> pt3.z == <span class="SNum">0</span>)
}

</span></div>
<h3 id="Accessing_Interface_Methods_Directly">Accessing Interface Methods Directly</h3>
<p>Implementation functions live under a scope named after the interface.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> pt2: <span class="SCst">Point2</span>
    <span class="SKwd">var</span> pt3: <span class="SCst">Point3</span>
    pt2.<span class="SCst">IReset</span>.<span class="SFct">set</span>(<span class="SNum">10</span>)
    pt2.<span class="SCst">IReset</span>.<span class="SFct">reset</span>()
    pt3.<span class="SCst">IReset</span>.<span class="SFct">set</span>(<span class="SNum">10</span>)
    pt3.<span class="SCst">IReset</span>.<span class="SFct">reset</span>()
}

</span></div>
<h3 id="Interface_as_a_Type">Interface as a Type</h3>
<p>An interface occupies two pointers: object pointer + virtual table pointer.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> pt2: <span class="SCst">Point2</span>
    <span class="SKwd">var</span> pt3: <span class="SCst">Point3</span>
    <span class="SKwd">var</span> itf = <span class="SKwd">cast</span>(<span class="SCst">IReset</span>) pt2
    <span class="SCmp">#assert</span>(<span class="SItr">#sizeof</span>(itf) == <span class="SNum">2</span> * <span class="SItr">#sizeof</span>(<span class="SItr">#null</span> *<span class="STpe">void</span>))

    <span class="SCmt">// Retrieve the concrete type with '@kindof'</span>
    itf = <span class="SKwd">cast</span>(<span class="SCst">IReset</span>) pt2
    <span class="SItr">@assert</span>(<span class="SItr">@kindof</span>(itf) == <span class="SCst">Point2</span>)
    itf = <span class="SKwd">cast</span>(<span class="SCst">IReset</span>) pt3
    <span class="SItr">@assert</span>(<span class="SItr">@kindof</span>(itf) == <span class="SCst">Point3</span>)

    <span class="SCmt">// Retrieve the concrete data with '@dataof'</span>
    itf = <span class="SKwd">cast</span>(<span class="SCst">IReset</span>) pt2
    <span class="SItr">@assert</span>(<span class="SItr">@dataof</span>(itf) == &amp;pt2)
    itf = <span class="SKwd">cast</span>(<span class="SCst">IReset</span>) pt3
    <span class="SItr">@assert</span>(<span class="SItr">@dataof</span>(itf) == &amp;pt3)
}

</span></div>
<h3 id="Default_Implementation_in_Interfaces">Default Implementation in Interfaces</h3>
<p>Provide default bodies directly in the interface. If a struct does not override, the default is used.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">interface</span> <span class="SCst">ITest</span>
{
    <span class="SKwd">mtd</span> <span class="SFct">isImplemented</span>()-&gt;<span class="STpe">bool</span>
    {
        <span class="SLgc">return</span> <span class="SKwd">false</span>
    }
}

</span></div>
<p>Override on <span class="code-inline">Point2</span>; no override on <span class="code-inline">Point3</span>.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">impl</span> <span class="SCst">ITest</span> <span class="SLgc">for</span> <span class="SCst">Point2</span>
{
    <span class="SKwd">mtd</span> <span class="SKwd">impl</span> <span class="SFct">isImplemented</span>()-&gt;<span class="STpe">bool</span>
    {
        <span class="SLgc">return</span> <span class="SKwd">true</span>
    }
}

<span class="SKwd">impl</span> <span class="SCst">ITest</span> <span class="SLgc">for</span> <span class="SCst">Point3</span> {}

</span></div>
<p>For <span class="code-inline">Point3</span>, <span class="code-inline">isImplemented()</span> returns <span class="code-inline">false</span> (the default).</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> v2: <span class="SCst">Point2</span>
    <span class="SKwd">var</span> v3: <span class="SCst">Point3</span>

    <span class="SKwd">let</span> i2 = <span class="SKwd">cast</span>(<span class="SCst">ITest</span>) v2
    <span class="SItr">@assert</span>(i2.<span class="SFct">isImplemented</span>())

    <span class="SKwd">let</span> i3 = <span class="SKwd">cast</span>(<span class="SCst">ITest</span>) v3
    <span class="SItr">@assert</span>(!i3.<span class="SFct">isImplemented</span>())
}

</span></div>
<h2 id="_007_000_functions_swg">Functions</h2>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>
</span></div>
<p>Functions cover more than calls and returns: Swag supports expression bodies, lambdas, closures, variadic parameters, overloads, UFCS, intentionally discarded results, and the <span class="code-inline">retval</span> return-type placeholder.</p>
<p>Macros, mixins, and foreign functions live in the metaprogramming and interoperability chapters because their execution model differs from an ordinary function call.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_007_001_declaration_swg">Declaration</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Function_Declarations">Function Declarations</h3>
<p>A function declaration starts with the <span class="code-inline">func</span> keyword, followed by the function name and parentheses. If no parameters are needed, the parentheses remain empty.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">toto</span>() {}

</span></div>
<h3 id="Returning_Values_from_Functions">Returning Values from Functions</h3>
<p>If a function returns a value, use <span class="code-inline">-&gt;</span> followed by the return type. The body must contain a <span class="code-inline">return</span> statement.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">toto1</span>()-&gt;<span class="STpe">s32</span>
{
    <span class="SLgc">return</span> <span class="SNum">0</span>
}

</span></div>
<h3 id="Inferring_Return_Types">Inferring Return Types</h3>
<p>Use <span class="code-inline">=&gt;</span> for simple expressions when the return type can be inferred automatically.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">sum</span>(x, y: <span class="STpe">s32</span>) =&gt; x + y

</span></div>
<h3 id="Defining_Parameters_in_Functions">Defining Parameters in Functions</h3>
<p>Parameters are declared within parentheses after the function name, each with a name and type.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">sum1</span>(x, y: <span class="STpe">s32</span>, unused: <span class="STpe">f32</span>)-&gt;<span class="STpe">s32</span>
{
    <span class="SLgc">return</span> x + y
}

</span></div>
<h3 id="Using_Default_Parameter_Values">Using Default Parameter Values</h3>
<p>Parameters may have default values, used when not provided by the caller.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">sum2</span>(x, y: <span class="STpe">s32</span>, unused: <span class="STpe">f32</span> = <span class="SNum">666</span>)-&gt;<span class="STpe">s32</span>
{
    <span class="SLgc">return</span> x + y
}

</span></div>
<h3 id="Inferred_Parameter_Types">Inferred Parameter Types</h3>
<p>If a parameter has a default value, its type can be inferred from it.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">sum3</span>(x, y = <span class="SNum">0.0</span>)
{
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(x) == <span class="STpe">f32</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(y) == <span class="STpe">f32</span>)
}

</span></div>
<h3 id="Overloading_Functions">Overloading Functions</h3>
<p>Multiple functions can share the same name if they differ in parameter count or types.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">enum</span> <span class="SCst">Values</span> { <span class="SCst">A</span>, <span class="SCst">B</span> }

<span class="SKwd">func</span> <span class="SFct">toto</span>(x: <span class="STpe">s32</span>, y = <span class="SCst">Values</span>.<span class="SCst">A</span>)
{
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(y) == <span class="SCst">Values</span>)
}

</span></div>
<h3 id="Nested_Functions">Nested Functions</h3>
<p>Functions can be nested within other functions for local logic organization. Nested functions are scoped, not closures.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">func</span> <span class="SFct">sub</span>(x, y: <span class="STpe">s32</span>) =&gt; x - y

    <span class="SKwd">let</span> x = <span class="SFct">sub</span>(<span class="SNum">5</span>, <span class="SNum">2</span>)
    <span class="SItr">@assert</span>(x == <span class="SNum">3</span>)
}

</span></div>
<h3 id="Named_Parameters_and_Parameter_Order">Named Parameters and Parameter Order</h3>
<p>Named parameters allow calling functions with arguments in any order.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">func</span> <span class="SFct">sub</span>(x, y: <span class="STpe">s32</span>) =&gt; x - y
    {
        <span class="SKwd">let</span> x1 = <span class="SFct">sub</span>(x: <span class="SNum">5</span>, y: <span class="SNum">2</span>)
        <span class="SItr">@assert</span>(x1 == <span class="SNum">3</span>)

        <span class="SKwd">let</span> x2 = <span class="SFct">sub</span>(y: <span class="SNum">5</span>, x: <span class="SNum">2</span>)
        <span class="SItr">@assert</span>(x2 == -<span class="SNum">3</span>)
    }

    {
        <span class="SKwd">func</span> <span class="SFct">returnMe</span>(x, y: <span class="STpe">s32</span> = <span class="SNum">0</span>) =&gt; x + y * <span class="SNum">2</span>
        <span class="SItr">@assert</span>(<span class="SFct">returnMe</span>(x: <span class="SNum">10</span>) == <span class="SNum">10</span>)
        <span class="SItr">@assert</span>(<span class="SFct">returnMe</span>(y: <span class="SNum">10</span>) == <span class="SNum">20</span>)
    }
}

</span></div>
<h3 id="Returning_Multiple_Values_with_Anonymous_Structs">Returning Multiple Values with Anonymous Structs</h3>
<p>Functions can return anonymous structs to conveniently hold multiple values. These can be accessed directly or destructured.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">func</span> <span class="SFct">myFunction</span>()-&gt;{ x, y: <span class="STpe">f32</span> }
    {
        <span class="SLgc">return</span> {<span class="SNum">1.0</span>, <span class="SNum">2.0</span>}
    }

    <span class="SKwd">let</span> result = <span class="SFct">myFunction</span>()
    <span class="SItr">@assert</span>(result.x == <span class="SNum">1.0</span>)
    <span class="SItr">@assert</span>(result.y == <span class="SNum">2.0</span>)
    <span class="SKwd">let</span> {x, y} = <span class="SFct">myFunction</span>()
    <span class="SItr">@assert</span>(x == <span class="SNum">1.0</span>)
    <span class="SItr">@assert</span>(y == <span class="SNum">2.0</span>)
    <span class="SKwd">let</span> {z, w} = <span class="SFct">myFunction</span>()
    <span class="SItr">@assert</span>(z == <span class="SNum">1.0</span>)
    <span class="SItr">@assert</span>(w == <span class="SNum">2.0</span>)
}

</span></div>
<h3 id="_007_002_lambda_swg">Lambda</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Lambdas">Lambdas</h3>
<p>A lambda in Swag is a pointer to a function. This allows functions to be stored in variables, passed as arguments, or returned from other functions—enabling functional programming patterns.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">func</span> <span class="SFct">myFunction0</span>() {}
    <span class="SKwd">func</span> <span class="SFct">myFunction1</span>(x: <span class="STpe">s32</span>) =&gt; x * x

    <span class="SKwd">let</span> ptr0: <span class="SKwd">func</span>() = &amp;myFunction0
    <span class="SFct">ptr0</span>()

    <span class="SKwd">let</span> ptr1 = &amp;myFunction1
    <span class="SItr">@assert</span>(<span class="SFct">myFunction1</span>(<span class="SNum">2</span>) == <span class="SNum">4</span>)
    <span class="SItr">@assert</span>(<span class="SFct">ptr1</span>(<span class="SNum">2</span>) == <span class="SNum">4</span>)
}

</span></div>
<h3 id="Null_Lambdas">Null Lambdas</h3>
<p>A lambda declared with the <span class="code-inline">#null</span> qualifier can be null, representing an absent function pointer. This is useful for optional callbacks or deferred initialization. A bare lambda type is non-null and must be initialized.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> lambda: <span class="SItr">#null</span> <span class="SKwd">func</span>()-&gt;<span class="STpe">bool</span>
    <span class="SItr">@assert</span>(lambda == <span class="SKwd">null</span>)
}

</span></div>
<h3 id="Using_Lambdas_as_Function_Parameters">Using Lambdas as Function Parameters</h3>
<p>Lambdas can be passed as arguments, enabling higher-order functions that call other functions dynamically.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">alias</span> <span class="SCst">Callback</span> = <span class="SKwd">func</span>(<span class="STpe">s32</span>)-&gt;<span class="STpe">s32</span>
    <span class="SKwd">func</span> <span class="SFct">toDo</span>(value: <span class="STpe">s32</span>, ptr: <span class="SCst">Callback</span>)-&gt;<span class="STpe">s32</span> =&gt; <span class="SFct">ptr</span>(value)

    <span class="SKwd">func</span> <span class="SFct">square</span>(x: <span class="STpe">s32</span>) =&gt; x * x
    <span class="SItr">@assert</span>(<span class="SFct">toDo</span>(<span class="SNum">4</span>, &amp;square) == <span class="SNum">16</span>)
}

</span></div>
<h3 id="Anonymous_Functions">Anonymous Functions</h3>
<p>Anonymous (inline) functions can be defined without names for short, inline logic.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> cb = <span class="SKwd">func</span>(x: <span class="STpe">s32</span>)-&gt;<span class="STpe">s32</span> =&gt; x * x
    <span class="SItr">@assert</span>(<span class="SFct">cb</span>(<span class="SNum">4</span>) == <span class="SNum">16</span>)

    cb = <span class="SKwd">func</span>(x: <span class="STpe">s32</span>)-&gt;<span class="STpe">s32</span> =&gt; x * x * x
    <span class="SItr">@assert</span>(<span class="SFct">cb</span>(<span class="SNum">4</span>) == <span class="SNum">64</span>)
}

</span></div>
<h3 id="Passing_Anonymous_Functions_as_Parameters">Passing Anonymous Functions as Parameters</h3>
<p>Anonymous functions can be passed directly as arguments.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">alias</span> <span class="SCst">Callback</span> = <span class="SKwd">func</span>(<span class="STpe">s32</span>)-&gt;<span class="STpe">s32</span>
    <span class="SKwd">func</span> <span class="SFct">toDo</span>(value: <span class="STpe">s32</span>, ptr: <span class="SCst">Callback</span>)-&gt;<span class="STpe">s32</span> =&gt; <span class="SFct">ptr</span>(value)

    <span class="SItr">@assert</span>(<span class="SFct">toDo</span>(<span class="SNum">4</span>, <span class="SKwd">func</span>(x: <span class="STpe">s32</span>) =&gt; x * x) == <span class="SNum">16</span>)
    <span class="SItr">@assert</span>(<span class="SFct">toDo</span>(<span class="SNum">4</span>, <span class="SKwd">func</span>(x: <span class="STpe">s32</span>) =&gt; x + x) == <span class="SNum">8</span>)
    <span class="SItr">@assert</span>(<span class="SFct">toDo</span>(<span class="SNum">4</span>, <span class="SKwd">func</span>(x: <span class="STpe">s32</span>)-&gt;<span class="STpe">s32</span> { <span class="SLgc">return</span> x - x; }) == <span class="SNum">0</span>)
}

</span></div>
<h3 id="Inferred_Parameter_Types_in_Anonymous_Functions">Inferred Parameter Types in Anonymous Functions</h3>
<p>If the type is clear from context, lambda parameters can omit explicit types.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">alias</span> <span class="SCst">Callback</span> = <span class="SKwd">func</span>(<span class="STpe">s32</span>)-&gt;<span class="STpe">s32</span>
    <span class="SKwd">func</span> <span class="SFct">toDo</span>(value: <span class="STpe">s32</span>, ptr: <span class="SCst">Callback</span>)-&gt;<span class="STpe">s32</span> =&gt; <span class="SFct">ptr</span>(value)

    <span class="SItr">@assert</span>(<span class="SFct">toDo</span>(<span class="SNum">4</span>, <span class="SKwd">func</span>(x) =&gt; x * x) == <span class="SNum">16</span>)
    <span class="SItr">@assert</span>(<span class="SFct">toDo</span>(<span class="SNum">4</span>, <span class="SKwd">func</span>(x) =&gt; x + x) == <span class="SNum">8</span>)
    <span class="SItr">@assert</span>(<span class="SFct">toDo</span>(<span class="SNum">4</span>, <span class="SKwd">func</span>(x) { <span class="SLgc">return</span> x - x; }) == <span class="SNum">0</span>)
}

</span></div>
<h3 id="Omitting_Types_When_Assigning_Lambdas">Omitting Types When Assigning Lambdas</h3>
<p>When the variable type is known, parameter and return types can be omitted in the lambda.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> fct: <span class="SItr">#null</span> <span class="SKwd">func</span>(<span class="STpe">s32</span>, <span class="STpe">s32</span>)-&gt;<span class="STpe">bool</span>

    fct = <span class="SKwd">func</span>(x, y) =&gt; x == y
    <span class="SItr">@assert</span>(<span class="SFct">fct</span>(<span class="SNum">10</span>, <span class="SNum">10</span>))

    fct = <span class="SKwd">func</span>(x, y) { <span class="SLgc">return</span> x != y }

    <span class="SItr">@assert</span>(<span class="SFct">fct</span>(<span class="SNum">20</span>, <span class="SNum">120</span>))
}

</span></div>
<h3 id="Lambdas_with_Default_Parameter_Values">Lambdas with Default Parameter Values</h3>
<p>Lambdas may have parameters with default values, allowing flexible invocation.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    {
        <span class="SKwd">let</span> x = <span class="SKwd">func</span>(val = <span class="SKwd">true</span>) { <span class="SItr">@assert</span>(val == <span class="SKwd">true</span>) }
        <span class="SFct">x</span>()
    }

    {
        <span class="SKwd">var</span> x: <span class="SItr">#null</span> <span class="SKwd">func</span>(val: <span class="STpe">bool</span> = <span class="SKwd">true</span>)
        x = <span class="SKwd">func</span>(val) { <span class="SItr">@assert</span>(val == <span class="SKwd">true</span>) }

        <span class="SFct">x</span>()
        <span class="SFct">x</span>(<span class="SKwd">true</span>)
    }
}

</span></div>
<h3 id="_007_003_closure_swg">Closure</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Closures">Closures</h3>
<p>Swag supports limited closures, allowing functions to capture variables from their surrounding scope. Up to 64 bytes can be captured without heap allocation.</p>
<p>A by-value capture is a plain byte copy into the closure: the closure never runs <span class="code-inline">opPostCopy</span> on the way in and never drops the captured value. Only simple types (without <span class="code-inline">opDrop</span>, <span class="code-inline">opPostCopy</span>, or <span class="code-inline">opPostMove</span>, and not marked <span class="code-inline">#[Swag.NoCopy]</span>) can therefore be captured by value; other types must be captured by reference with <span class="code-inline">&amp;</span>.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="Declaring_a_Closure">Declaring a Closure</h3>
<p>A closure is declared like a lambda, with captured variables listed between <span class="code-inline">|...|</span> before the parameter list. The type uses <span class="code-inline">func||(...)</span>.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> a = <span class="SNum">125</span>
    <span class="SKwd">let</span> b = <span class="SNum">521</span>

    <span class="SKwd">let</span> fct: <span class="SKwd">func</span>||() = <span class="SKwd">func</span>|a, b|()
    {
        <span class="SItr">@assert</span>(a == <span class="SNum">125</span>)
        <span class="SItr">@assert</span>(b == <span class="SNum">521</span>)
    }

    <span class="SFct">fct</span>()
}

</span></div>
<h3 id="Init-Capture_and_Aliases">Init-Capture and Aliases</h3>
<p>Use 'name = expr' to capture the value of an expression under a chosen name. This is useful when capturing a member path, a computed value, or <span class="code-inline">me</span> under a clear callback-local name.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">struct</span> <span class="SCst">Box</span>
    {
        value: <span class="STpe">s32</span>
    }

    <span class="SKwd">let</span> leftBox  = <span class="SCst">Box</span>{<span class="SNum">2</span>}
    <span class="SKwd">let</span> rightBox = <span class="SCst">Box</span>{<span class="SNum">7</span>}

    <span class="SKwd">let</span> fct: <span class="SKwd">func</span>||()-&gt;<span class="STpe">s32</span> = <span class="SKwd">func</span>|left = leftBox.value, right = rightBox.value|()-&gt;<span class="STpe">s32</span> { <span class="SLgc">return</span> left * <span class="SNum">10</span> + right }

    <span class="SItr">@assert</span>(<span class="SFct">fct</span>() == <span class="SNum">27</span>)
}

</span></div>
<h3 id="Capturing_Variables_by_Reference">Capturing Variables by Reference</h3>
<p>Use <span class="code-inline">&amp;</span> to capture by reference; otherwise, capture is by value.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> a = <span class="SNum">125</span>

    <span class="SKwd">let</span> fct: <span class="SKwd">func</span>||() = <span class="SKwd">func</span>|&amp;a|() { a += <span class="SNum">1</span> }

    <span class="SFct">fct</span>()
    <span class="SItr">@assert</span>(a == <span class="SNum">126</span>)

    <span class="SFct">fct</span>()
    <span class="SItr">@assert</span>(a == <span class="SNum">127</span>)
}

</span></div>
<h3 id="Aliased_Reference_Capture">Aliased Reference Capture</h3>
<p>The <span class="code-inline">&amp;</span> form can also be used with an alias when the captured expression is addressable.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> a = <span class="SNum">125</span>

    <span class="SKwd">let</span> fct: <span class="SKwd">func</span>||()-&gt;<span class="STpe">s32</span> = <span class="SKwd">func</span>|&amp;current = a|()-&gt;<span class="STpe">s32</span>
    {
        current += <span class="SNum">1</span>
        <span class="SLgc">return</span> current
    }

    <span class="SItr">@assert</span>(<span class="SFct">fct</span>() == <span class="SNum">126</span>)
    <span class="SItr">@assert</span>(a == <span class="SNum">126</span>)
}

</span></div>
<h3 id="Assigning_Lambdas_to_Closure_Variables">Assigning Lambdas to Closure Variables</h3>
<p>A closure variable can also hold a regular lambda (no captures).</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> fct: <span class="SItr">#null</span> <span class="SKwd">func</span>||(<span class="STpe">s32</span>, <span class="STpe">s32</span>)-&gt;<span class="STpe">s32</span>

    fct = <span class="SKwd">func</span>(x, y) =&gt; x + y
    <span class="SItr">@assert</span>(<span class="SFct">fct</span>(<span class="SNum">1</span>, <span class="SNum">2</span>) == <span class="SNum">3</span>)
}

</span></div>
<h3 id="Capturing_Complex_Types">Capturing Complex Types</h3>
<p>Arrays, structs, and slices can be captured by value if they fit in the capture size and are plain data (POD).</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> x = [<span class="SNum">1</span>, <span class="SNum">2</span>, <span class="SNum">3</span>]
    <span class="SKwd">var</span> fct: <span class="SItr">#null</span> <span class="SKwd">func</span>||(<span class="STpe">s32</span>)-&gt;<span class="STpe">s32</span>
    fct = <span class="SKwd">func</span>|x|(toAdd)
    {
        <span class="SKwd">var</span> res = <span class="SNum">0</span>
        <span class="SLgc">for</span> v <span class="SLgc">in</span> x <span class="SLgc">do</span>
            res += v
        res     += toAdd
        <span class="SLgc">return</span> res
    }
    <span class="SKwd">let</span> result = <span class="SFct">fct</span>(<span class="SNum">4</span>)
    <span class="SItr">@assert</span>(result == <span class="SNum">1</span> + <span class="SNum">2</span> + <span class="SNum">3</span> + <span class="SNum">4</span>)
}

</span></div>
<h3 id="Modifying_Captured_Variables">Modifying Captured Variables</h3>
<p>Captured values belong to the closure and can be mutated, enabling stateful behavior.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">func</span> <span class="SFct">getInc</span>()-&gt;<span class="SKwd">func</span>||()-&gt;<span class="STpe">s32</span>
    {
        <span class="SKwd">let</span> x = <span class="SNum">10</span>

        <span class="SLgc">return</span> <span class="SKwd">func</span>|x|()-&gt;<span class="STpe">s32</span>
        {
            x += <span class="SNum">1</span>
            <span class="SLgc">return</span> x
        }
    }

    <span class="SKwd">let</span> fct = <span class="SFct">getInc</span>()

    <span class="SItr">@assert</span>(<span class="SFct">fct</span>() == <span class="SNum">11</span>)
    <span class="SItr">@assert</span>(<span class="SFct">fct</span>() == <span class="SNum">12</span>)
    <span class="SItr">@assert</span>(<span class="SFct">fct</span>() == <span class="SNum">13</span>)
}

</span></div>
<h3 id="_007_004_variadic_parameters_swg">Variadic Parameters</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Variadic_Functions">Variadic Functions</h3>
<p>Variadic functions accept a variable number of arguments using <span class="code-inline">...</span>. They allow flexibility in cases where the number of arguments is not known in advance.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">func</span> <span class="SFct">myFunction</span>(value: <span class="STpe">bool</span>, parameters: ...)
    {
    <span class="SCmt">// This function can accept any number of extra arguments after 'value'.</span>
    }

    <span class="SFct">myFunction</span>(<span class="SKwd">true</span>, <span class="SNum">4</span>, <span class="SStr">"true"</span>, <span class="SNum">5.6</span>)     <span class="SCmt">// Passes extra arguments after 'value'</span>
}

</span></div>
<h3 id="Working_with_Variadic_Parameters_as_Slices">Working with Variadic Parameters as Slices</h3>
<p>Variadic parameters are treated as slices of type <span class="code-inline">any</span>, allowing you to process mixed argument types dynamically.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">func</span> <span class="SFct">myFunction</span>(parameters: ...)
    {
        <span class="SCmt">// Check the number of arguments</span>
        <span class="SItr">@assert</span>(<span class="SItr">@countof</span>(parameters) == <span class="SNum">3</span>)

        <span class="SCmt">// Initially, each parameter is of type 'any'</span>
        <span class="SCmp">#assert</span>(<span class="SItr">#nameof</span>(<span class="SItr">#typeof</span>(parameters[<span class="SNum">0</span>])) == <span class="SStr">"any"</span>)
        <span class="SCmp">#assert</span>(<span class="SItr">#nameof</span>(<span class="SItr">#typeof</span>(parameters[<span class="SNum">1</span>])) == <span class="SStr">"any"</span>)
        <span class="SCmp">#assert</span>(<span class="SItr">#nameof</span>(<span class="SItr">#typeof</span>(parameters[<span class="SNum">2</span>])) == <span class="SStr">"any"</span>)

        <span class="SCmt">// Determine actual runtime types</span>
        <span class="SItr">@assert</span>(<span class="SItr">@kindof</span>(parameters[<span class="SNum">0</span>]) == <span class="STpe">s32</span>)
        <span class="SItr">@assert</span>(<span class="SItr">@kindof</span>(parameters[<span class="SNum">1</span>]) == <span class="STpe">string</span>)
        <span class="SItr">@assert</span>(<span class="SItr">@kindof</span>(parameters[<span class="SNum">2</span>]) == <span class="STpe">f32</span>)
    }

    <span class="SFct">myFunction</span>(<span class="SNum">4</span>, <span class="SStr">"true"</span>, <span class="SNum">5.6</span>'<span class="STpe">f32</span>)
}

</span></div>
<h3 id="Forcing_Variadic_Parameters_to_a_Specific_Type">Forcing Variadic Parameters to a Specific Type</h3>
<p>When all arguments are of the same type, you can enforce it using type annotations. This prevents parameters from defaulting to <span class="code-inline">any</span>.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">func</span> <span class="SFct">myFunction</span>(value: <span class="STpe">bool</span>, parameters: <span class="STpe">s32</span>...)
    {
        <span class="SCmt">// All 'parameters' elements must be of type 's32'</span>
        <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(parameters[<span class="SNum">0</span>]).name == <span class="SStr">"s32"</span>)
        <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(parameters[<span class="SNum">1</span>]).name == <span class="SStr">"s32"</span>)
        <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(parameters[<span class="SNum">2</span>]) == <span class="STpe">s32</span>)
        <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(parameters[<span class="SNum">3</span>]) == <span class="STpe">s32</span>)

        <span class="SCmt">// Check values</span>
        <span class="SItr">@assert</span>(parameters[<span class="SNum">0</span>] == <span class="SNum">10</span>)
        <span class="SItr">@assert</span>(parameters[<span class="SNum">1</span>] == <span class="SNum">20</span>)
        <span class="SItr">@assert</span>(parameters[<span class="SNum">2</span>] == <span class="SNum">30</span>)
        <span class="SItr">@assert</span>(parameters[<span class="SNum">3</span>] == <span class="SNum">40</span>)
    }

    <span class="SFct">myFunction</span>(<span class="SKwd">true</span>, <span class="SNum">10</span>, <span class="SNum">20</span>, <span class="SNum">30</span>, <span class="SNum">40</span>)
}

</span></div>
<h3 id="Passing_Variadic_Parameters_Between_Functions">Passing Variadic Parameters Between Functions</h3>
<p>Variadic parameters can be forwarded between functions while preserving their types and values.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">func</span> <span class="SFct">A</span>(params: ...)
    {
        <span class="SItr">@assert</span>(<span class="SItr">@countof</span>(params) == <span class="SNum">2</span>)
        <span class="SItr">@assert</span>(<span class="SItr">@kindof</span>(params[<span class="SNum">0</span>]) == <span class="STpe">string</span>)
        <span class="SItr">@assert</span>(<span class="SItr">@kindof</span>(params[<span class="SNum">1</span>]) == <span class="STpe">bool</span>)
        <span class="SItr">@assert</span>(<span class="SKwd">cast</span>(<span class="STpe">string</span>) params[<span class="SNum">0</span>] == <span class="SStr">"value"</span>)
        <span class="SItr">@assert</span>(<span class="SKwd">cast</span>(<span class="STpe">bool</span>) params[<span class="SNum">1</span>] == <span class="SKwd">true</span>)
    }

    <span class="SKwd">func</span> <span class="SFct">B</span>(params: ...)
    {
        <span class="SFct">A</span>(params)     <span class="SCmt">// Forward the parameters</span>
    }

    <span class="SFct">B</span>(<span class="SStr">"value"</span>, <span class="SKwd">true</span>)
}

</span></div>
<h3 id="Combining_Fixed_and_Variadic_Parameters">Combining Fixed and Variadic Parameters</h3>
<p>You can mix fixed parameters with variadic ones to make function calls more expressive.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">internal</span> <span class="SKwd">func</span> <span class="SFct">print</span>()
{
    <span class="SKwd">func</span> <span class="SFct">logMessage</span>(prefix: <span class="STpe">string</span>, messages: ...)
    {
        <span class="SLgc">for</span> msg <span class="SLgc">in</span> messages
        {
            <span class="SItr">@print</span>(prefix, <span class="SStr">" =&gt; "</span>, <span class="SKwd">cast</span>(<span class="STpe">string</span>) msg)
        }
    }

    <span class="SFct">logMessage</span>(<span class="SStr">"Error:"</span>, <span class="SStr">"File not found"</span>, <span class="SStr">"Access denied"</span>, <span class="SStr">"Disk full"</span>)
}

</span></div>
<h3 id="Handling_Different_Types_in_Variadic_Parameters">Handling Different Types in Variadic Parameters</h3>
<p>Handle mixed-type parameters dynamically, performing type-specific actions.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">func</span> <span class="SFct">processParameters</span>(params: ...)-&gt;<span class="STpe">s32</span>
    {
        <span class="SKwd">var</span> sum = <span class="SNum">0</span>

        <span class="SLgc">for</span> p <span class="SLgc">in</span> params
        {
            <span class="SLgc">switch</span> <span class="SItr">@kindof</span>(p)
            {
            <span class="SLgc">case</span> <span class="STpe">s32</span>:    sum += <span class="SNum">1</span>
            <span class="SLgc">case</span> <span class="STpe">string</span>: sum += <span class="SNum">10</span>
            }
        }

        <span class="SLgc">return</span> sum
    }

    <span class="SKwd">let</span> result = <span class="SFct">processParameters</span>(<span class="SNum">1</span>, <span class="SNum">2</span>, <span class="SStr">"Hello, "</span>, <span class="SNum">3</span>, <span class="SStr">"World!"</span>)
    <span class="SItr">@assert</span>(result == <span class="SNum">1</span> + <span class="SNum">1</span> + <span class="SNum">10</span> + <span class="SNum">1</span> + <span class="SNum">10</span>)
}

</span></div>
<h3 id="_007_005_function_overloading_swg">Function Overloading</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Function_Overloading">Function Overloading</h3>
<p>Swag allows multiple functions to share the same name when their parameter signatures differ. This feature, called <i>function overloading</i>, enables writing concise and intuitive APIs. The compiler chooses the correct overload from the call arguments.</p>
<div class="code-block"><span class="SCde">
<span class="SAtr">#[Swag.ConstExpr]</span>
{
    <span class="SCmt">// Overload: two parameters</span>
    <span class="SKwd">func</span> <span class="SFct">sum</span>(x, y: <span class="STpe">s32</span>) =&gt; x + y

    <span class="SCmt">// Overload: three parameters</span>
    <span class="SKwd">func</span> <span class="SFct">sum</span>(x, y, z: <span class="STpe">s32</span>) =&gt; x + y + z
}

</span></div>
<p>The compiler chooses the correct overload based on the number and types of arguments. This allows calling <span class="code-inline">sum</span> naturally for different scenarios.</p>
<div class="code-block"><span class="SCde">
<span class="SCmp">#assert</span>(<span class="SFct">sum</span>(<span class="SNum">1</span>, <span class="SNum">2</span>) == <span class="SNum">3</span>)        <span class="SCmt">// Calls the two-parameter version</span>
<span class="SCmp">#assert</span>(<span class="SFct">sum</span>(<span class="SNum">1</span>, <span class="SNum">2</span>, <span class="SNum">3</span>) == <span class="SNum">6</span>)     <span class="SCmt">// Calls the three-parameter version</span>

</span></div>
<h3 id="_007_006_ufcs_swg">Ufcs</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Uniform_Function_Call_Syntax__UFCS_">Uniform Function Call Syntax (UFCS)</h3>
<p><i>UFCS</i> (Uniform Function Call Syntax) allows a function to be called in the <span class="code-inline">param.func()</span> form when the first parameter type of <span class="code-inline">func()</span> matches <span class="code-inline">param</span>. This enables calling standalone functions as if they were instance methods, improving readability.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">func</span> <span class="SFct">myFunc</span>(param: <span class="STpe">bool</span>) =&gt; param

    <span class="SKwd">let</span> b = <span class="SKwd">false</span>
    <span class="SItr">@assert</span>(<span class="SFct">myFunc</span>(b) == b.<span class="SFct">myFunc</span>())     <span class="SCmt">// UFCS allows method-like syntax</span>
}

</span></div>
<h3 id="Static_Functions_as_Methods">Static Functions as Methods</h3>
<p>All functions in Swag are static, but UFCS enables them to be invoked with instance-style syntax. This improves clarity when working with structs or objects.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">struct</span> <span class="SCst">Point</span>
    {
        x, y: <span class="STpe">s32</span>
    }

    <span class="SKwd">func</span> <span class="SFct">set</span>(pt: *<span class="SCst">Point</span>, value: <span class="STpe">s32</span>)
    {
        pt.x, pt.y = value
    }

    <span class="SKwd">var</span> pt: <span class="SCst">Point</span>

    <span class="SCmt">// UFCS - called like a method</span>
    pt.<span class="SFct">set</span>(<span class="SNum">10</span>)
    <span class="SItr">@assert</span>(pt.x == <span class="SNum">10</span> <span class="SLgc">and</span> pt.y == <span class="SNum">10</span>)

    <span class="SCmt">// Normal static function call</span>
    <span class="SFct">set</span>(&amp;pt, <span class="SNum">20</span>)
    <span class="SItr">@assert</span>(pt.x == <span class="SNum">20</span> <span class="SLgc">and</span> pt.y == <span class="SNum">20</span>)
}

</span></div>
<h3 id="UFCS_with_Multiple_Parameters">UFCS with Multiple Parameters</h3>
<p>UFCS works with multi-parameter functions as long as the first parameter type matches the instance type.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">struct</span> <span class="SCst">Vector</span>
    {
        x, y: <span class="STpe">f32</span>
    }

    <span class="SKwd">func</span> <span class="SFct">add</span>(vec: *<span class="SCst">Vector</span>, dx: <span class="STpe">f32</span>, dy: <span class="STpe">f32</span>)
    {
        vec.x += dx
        vec.y += dy
    }

    <span class="SKwd">var</span> v: <span class="SCst">Vector</span>

    <span class="SCmt">// UFCS style</span>
    v.<span class="SFct">add</span>(<span class="SNum">1.0</span>, <span class="SNum">2.0</span>)
    <span class="SItr">@assert</span>(v.x == <span class="SNum">1.0</span> <span class="SLgc">and</span> v.y == <span class="SNum">2.0</span>)

    <span class="SCmt">// Standard function call</span>
    <span class="SFct">add</span>(&amp;v, <span class="SNum">3.0</span>, <span class="SNum">4.0</span>)
    <span class="SItr">@assert</span>(v.x == <span class="SNum">4.0</span> <span class="SLgc">and</span> v.y == <span class="SNum">6.0</span>)
}

</span></div>
<h3 id="UFCS_and_Function_Overloading">UFCS and Function Overloading</h3>
<p>UFCS supports overloaded functions, selecting the correct overload based on argument types.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">struct</span> <span class="SCst">Complex</span>
    {
        real, imag: <span class="STpe">f32</span>
    }

    <span class="SKwd">func</span> <span class="SFct">multiply</span>(c: *<span class="SCst">Complex</span>, scalar: <span class="STpe">f32</span>)
    {
        c.real *= scalar
        c.imag *= scalar
    }

    <span class="SKwd">func</span> <span class="SFct">multiply</span>(c: *<span class="SCst">Complex</span>, other: *<span class="SCst">Complex</span>)
    {
        <span class="SCmt">// Use temporary variables to prevent reuse of modified values</span>
        <span class="SKwd">let</span> r = (c.real * other.real) - (c.imag * other.imag)
        <span class="SKwd">let</span> i = (c.real * other.imag) + (c.imag * other.real)
        c.real = r
        c.imag = i
    }

    <span class="SKwd">var</span> c1 = <span class="SCst">Complex</span>{<span class="SNum">2.0</span>, <span class="SNum">3.0</span>}
    <span class="SKwd">var</span> c2 = <span class="SCst">Complex</span>{<span class="SNum">4.0</span>, <span class="SNum">5.0</span>}

    <span class="SCmt">// UFCS: multiply by scalar</span>
    c1.<span class="SFct">multiply</span>(<span class="SNum">2.0</span>)
    <span class="SItr">@assert</span>(c1.real == <span class="SNum">4.0</span> <span class="SLgc">and</span> c1.imag == <span class="SNum">6.0</span>)

    <span class="SCmt">// UFCS: multiply by another complex number</span>
    c1.<span class="SFct">multiply</span>(&amp;c2)
    <span class="SItr">@assert</span>(c1.real == -<span class="SNum">14.0</span> <span class="SLgc">and</span> c1.imag == <span class="SNum">44.0</span>)
}

</span></div>
<h3 id="_007_007_discard_swg">Discard</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Return_Value_Usage">Return Value Usage</h3>
<p>Swag enforces that all function return values must be used. If a function’s result is ignored, the compiler raises an error. This prevents accidental omission of important results and ensures deliberate handling of all return values.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">func</span> <span class="SFct">sum</span>(x, y: <span class="STpe">s32</span>) =&gt; x + y

    <span class="SCmt">// Uncommenting the following line would cause a compile-time error:</span>
    <span class="SCmt">// sum(2, 3)</span>

    <span class="SCmt">// Use 'discard' to explicitly ignore the return value</span>
    <span class="SKwd">discard</span> <span class="SFct">sum</span>(<span class="SNum">2</span>, <span class="SNum">3</span>)
}

</span></div>
<h3 id="_Swag_Discardable__Attribute"><span class="code-inline">Swag.Discardable</span> Attribute</h3>
<p>Marking a function with <span class="code-inline">#[Swag.Discardable]</span> allows its return value to be safely ignored. Use this for utility functions whose results are optional.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SAtr">#[Swag.Discardable]</span>
    <span class="SKwd">func</span> <span class="SFct">mul</span>(x, y: <span class="STpe">s32</span>)-&gt;<span class="STpe">s32</span> =&gt; x * y

    <span class="SCmt">// Return value can be ignored without using 'discard'</span>
    <span class="SFct">mul</span>(<span class="SNum">2</span>, <span class="SNum">4</span>)
}

</span></div>
<h3 id="_007_008_retval_swg">Retval</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="The__retval__Special_Type">The <span class="code-inline">retval</span> Special Type</h3>
<p>In Swag, <span class="code-inline">retval</span> represents the current function’s return type. It allows you to declare and manipulate the return value directly inside the function, without repeating the type declaration. This improves code readability and flexibility, especially when working with complex or generic return types.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">func</span> <span class="SFct">toto</span>()-&gt;<span class="STpe">s32</span>
    {
        <span class="SKwd">var</span> result: <span class="SKwd">retval</span>     <span class="SCmt">// 'retval' resolves to 's32' in this context.</span>
        result = <span class="SNum">10</span>
        <span class="SLgc">return</span> result
    }

    <span class="SItr">@assert</span>(<span class="SFct">toto</span>() == <span class="SNum">10</span>)
}

</span></div>
<h3 id="Optimizing_Return_Values">Optimizing Return Values</h3>
<p>A <span class="code-inline">retval</span> local <i>is</i> the return value: the compiler gives it the caller’s memory, so filling it in costs no copy at the end of the function. This is especially beneficial when returning large structs, arrays, or tuples.</p>
<p>Returning an aggregate literal needs no annotation for this — <span class="code-inline">return RGB{0.5, 0.1, 1.0}</span> is already built in the caller’s memory. Reach for <span class="code-inline">retval</span> when the value is filled in step by step, or when the return type has no name you could write.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">struct</span> <span class="SCst">RGB</span>
    {
        x, y, z: <span class="STpe">f64</span>
    }

    <span class="SKwd">func</span> <span class="SFct">getWhite</span>()-&gt;<span class="SCst">RGB</span>
    {
        <span class="SCmt">// 'retval = undefined' prevents unnecessary clearing of the return structure.</span>
        <span class="SKwd">var</span> result: <span class="SKwd">retval</span> = <span class="SKwd">undefined</span>
        result.x = <span class="SNum">0.5</span>
        result.y = <span class="SNum">0.1</span>
        result.z = <span class="SNum">1.0</span>
        <span class="SLgc">return</span> result
    }

    <span class="SKwd">let</span> {r, g, b} = <span class="SFct">getWhite</span>()
    <span class="SItr">@assert</span>(r == <span class="SNum">0.5</span>)
    <span class="SItr">@assert</span>(g == <span class="SNum">0.1</span>)
    <span class="SItr">@assert</span>(b == <span class="SNum">1.0</span>)
}

</span></div>
<h3 id="Returning_Arrays_Efficiently">Returning Arrays Efficiently</h3>
<p>When returning large data structures like arrays, using <span class="code-inline">retval</span> avoids redundant initialization or copying, resulting in faster, more memory-efficient code.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">func</span> <span class="SFct">toto</span>()-&gt;[<span class="SNum">255</span>] <span class="STpe">s32</span>
    {
        <span class="SKwd">var</span> result: <span class="SKwd">retval</span> = <span class="SKwd">undefined</span>
        <span class="SLgc">for</span> [i] <span class="SLgc">in</span> <span class="SNum">255</span> <span class="SLgc">do</span>
            result[i] = i
        <span class="SLgc">return</span> result
    }

    <span class="SKwd">var</span> arr = <span class="SFct">toto</span>()
    <span class="SItr">@assert</span>(arr[<span class="SNum">0</span>] == <span class="SNum">0</span>)
    <span class="SItr">@assert</span>(arr[<span class="SNum">100</span>] == <span class="SNum">100</span>)
    <span class="SItr">@assert</span>(arr[<span class="SNum">254</span>] == <span class="SNum">254</span>)
}

</span></div>
<h2 id="_008_000_intrinsics_swg">Intrinsics</h2>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Intrinsics">Intrinsics</h3>
<p>Intrinsics are operations implemented directly by the compiler or its runtime. Their names start with <span class="code-inline">@</span>, so they cannot collide with application APIs. They cover five broad areas:</p>
<ul>
<li>assertions, diagnostics, execution context, and compiler access;</li>
<li>type erasure, reflection, and construction of slices or strings;</li>
<li>explicit value lifecycle operations;</li>
<li>math, bit, memory, and atomic primitives;</li>
<li>interoperability with C variadic functions.</li>
</ul>
<p>Use an intrinsic when its semantics are genuinely language-level or low-level. Prefer a typed library abstraction for ownership, platform APIs, containers, and application-level behavior.</p>
<h3 id="Compile_Time_and_Runtime">Compile Time and Runtime</h3>
<p>Many pure intrinsics accept constant operands and are evaluated by the compiler. The same call can also execute at runtime when an operand is dynamic.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">const</span> <span class="SCst">IntrinsicCompileTimeMinimum</span> = <span class="SItr">@min</span>(<span class="SNum">12</span>'<span class="STpe">s32</span>, <span class="SNum">7</span>'<span class="STpe">s32</span>)
<span class="SCmp">#assert</span>(<span class="SCst">IntrinsicCompileTimeMinimum</span> == <span class="SNum">7</span>)

<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> left:  <span class="STpe">s32</span> = <span class="SNum">12</span>
    <span class="SKwd">let</span> right: <span class="STpe">s32</span> = <span class="SNum">7</span>
    <span class="SItr">@assert</span>(<span class="SItr">@min</span>(left, right) == <span class="SNum">7</span>)
}

</span></div>
<h3 id="Failure_Behavior">Failure Behavior</h3>
<p><span class="code-inline">@assert</span> and <span class="code-inline">@panic</span> stop execution. Compiler-facing code can report diagnostics with <span class="code-inline">@compilererror</span> and <span class="code-inline">@compilerwarning</span>. Memory and math intrinsics are also subject to the safety and sanity policies described later in this reference.</p>
<div class="blockquote blockquote-warning">
<div class="blockquote-title-block"><span class="blockquote-title">Warning</span></div>
<p>Intrinsics do not imply ownership. <span class="code-inline">@mkslice</span> and <span class="code-inline">@mkstring</span> create views; <span class="code-inline">@alloc</span> returns raw storage; <span class="code-inline">@memcpy</span> ignores value lifecycle hooks. The caller remains responsible for lifetime, bounds, alignment, and element semantics.</p>
</div>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_008_001_init_swg">Init</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="__init__Intrinsic"><span class="code-inline">@init</span> Intrinsic</h3>
<p>Reinitializes a variable or memory region to either its type default value or a provided custom value (tuple for aggregates).</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="Scalars_-_Default_Initialization">Scalars - Default Initialization</h3>
<p>Reinitialize a single variable to its default value.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> x = <span class="SNum">666</span>
    <span class="SItr">@init</span>(x)     <span class="SCmt">// Reset variable 'x' to its default (0)</span>
    <span class="SItr">@assert</span>(x == <span class="SNum">0</span>)
}

</span></div>
<h3 id="Scalars_-_Initialization_with_a_Specific_Value">Scalars - Initialization with a Specific Value</h3>
<p>Reinitialize a variable with a custom value instead of its default.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> x = <span class="SNum">666</span>'<span class="STpe">f32</span>
    <span class="SItr">@init</span>(x)(<span class="SNum">3.14</span>)     <span class="SCmt">// Initialize variable 'x' with 3.14 instead of 0</span>
    <span class="SItr">@assert</span>(x == <span class="SNum">3.14</span>)
}

</span></div>
<h3 id="Arrays_-_Count-Based_Default_Initialization">Arrays - Count-Based Default Initialization</h3>
<p>Reinitialize a specified number of elements in an array or memory block.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> x = [<span class="SNum">1</span>, <span class="SNum">2</span>]

    <span class="SItr">@init</span>(&amp;x, <span class="SNum">2</span>)     <span class="SCmt">// Reset first 2 elements to their default (0)</span>
    <span class="SItr">@assert</span>(x[<span class="SNum">0</span>] == <span class="SNum">0</span>)
    <span class="SItr">@assert</span>(x[<span class="SNum">1</span>] == <span class="SNum">0</span>)

    x[<span class="SNum">0</span>] = <span class="SNum">1</span>
    x[<span class="SNum">1</span>] = <span class="SNum">2</span>

    <span class="SItr">@init</span>(x)     <span class="SCmt">// Reset the entire array to default values</span>
    <span class="SItr">@assert</span>(x[<span class="SNum">0</span>] == <span class="SNum">0</span>)
    <span class="SItr">@assert</span>(x[<span class="SNum">1</span>] == <span class="SNum">0</span>)
}

</span></div>
<h3 id="Arrays_-_Initialization_with_a_Specific_Value">Arrays - Initialization with a Specific Value</h3>
<p>Initialize all targeted elements in an array to a given value.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> x = [<span class="SNum">1</span>, <span class="SNum">2</span>]

    <span class="SItr">@init</span>(&amp;x, <span class="SNum">2</span>)(<span class="SNum">555</span>)     <span class="SCmt">// Initialize both elements to 555</span>
    <span class="SItr">@assert</span>(x[<span class="SNum">0</span>] == <span class="SNum">555</span>)
    <span class="SItr">@assert</span>(x[<span class="SNum">1</span>] == <span class="SNum">555</span>)
}

</span></div>
<h3 id="Structs_-_Reset_to_Declared_Defaults">Structs - Reset to Declared Defaults</h3>
<p>Reinitialize a struct instance to its declared default field values.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">struct</span> <span class="SCst">RGB</span>
    {
        r = <span class="SNum">1</span>, g = <span class="SNum">2</span>, b = <span class="SNum">3</span>
    }

    <span class="SKwd">var</span> rgb = <span class="SCst">RGB</span>{<span class="SNum">10</span>, <span class="SNum">20</span>, <span class="SNum">30</span>}
    <span class="SItr">@assert</span>(rgb.r == <span class="SNum">10</span>)
    <span class="SItr">@assert</span>(rgb.g == <span class="SNum">20</span>)
    <span class="SItr">@assert</span>(rgb.b == <span class="SNum">30</span>)

    <span class="SItr">@init</span>(rgb)     <span class="SCmt">// Reset struct fields to their declared defaults</span>
    <span class="SItr">@assert</span>(rgb.r == <span class="SNum">1</span>)
    <span class="SItr">@assert</span>(rgb.g == <span class="SNum">2</span>)
    <span class="SItr">@assert</span>(rgb.b == <span class="SNum">3</span>)
}

</span></div>
<h3 id="Structs_-_Initialization_with_Specific_Field_Values">Structs - Initialization with Specific Field Values</h3>
<p>Reinitialize a struct instance with custom field values.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">struct</span> <span class="SCst">RGB</span>
    {
        r = <span class="SNum">1</span>, g = <span class="SNum">2</span>, b = <span class="SNum">3</span>
    }

    <span class="SKwd">var</span> rgb = <span class="SCst">RGB</span>{<span class="SNum">10</span>, <span class="SNum">20</span>, <span class="SNum">30</span>}
    <span class="SItr">@assert</span>(rgb.r == <span class="SNum">10</span>)
    <span class="SItr">@assert</span>(rgb.g == <span class="SNum">20</span>)
    <span class="SItr">@assert</span>(rgb.b == <span class="SNum">30</span>)

    <span class="SItr">@init</span>(rgb)(<span class="SNum">5</span>, <span class="SNum">6</span>, <span class="SNum">7</span>)     <span class="SCmt">// Assign new custom values to all struct fields</span>
    <span class="SItr">@assert</span>(rgb.r == <span class="SNum">5</span>)
    <span class="SItr">@assert</span>(rgb.g == <span class="SNum">6</span>)
    <span class="SItr">@assert</span>(rgb.b == <span class="SNum">7</span>)
}

</span></div>
<h3 id="Arrays_of_Structs_-_Bulk_Initialization_and_Reinitialization">Arrays of Structs - Bulk Initialization and Reinitialization</h3>
<p>Reinitialize all elements of an array of structs with specified field values.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">struct</span> <span class="SCst">RGB</span>
    {
        r = <span class="SNum">1</span>, g = <span class="SNum">2</span>, b = <span class="SNum">3</span>
    }

    <span class="SKwd">var</span> rgb: [<span class="SNum">4</span>] <span class="SCst">RGB</span>

    <span class="SItr">@init</span>(&amp;rgb, <span class="SNum">4</span>)(<span class="SNum">5</span>, <span class="SNum">6</span>, <span class="SNum">7</span>)     <span class="SCmt">// Initialize all 4 elements with (5, 6, 7)</span>
    <span class="SItr">@assert</span>(rgb[<span class="SNum">3</span>].r == <span class="SNum">5</span>)
    <span class="SItr">@assert</span>(rgb[<span class="SNum">3</span>].g == <span class="SNum">6</span>)
    <span class="SItr">@assert</span>(rgb[<span class="SNum">3</span>].b == <span class="SNum">7</span>)

    <span class="SItr">@init</span>(rgb)(<span class="SNum">50</span>, <span class="SNum">60</span>, <span class="SNum">70</span>)     <span class="SCmt">// Reinitialize entire array with new values</span>
    <span class="SItr">@assert</span>(rgb[<span class="SNum">3</span>].r == <span class="SNum">50</span>)
    <span class="SItr">@assert</span>(rgb[<span class="SNum">3</span>].g == <span class="SNum">60</span>)
    <span class="SItr">@assert</span>(rgb[<span class="SNum">3</span>].b == <span class="SNum">70</span>)
}

</span></div>
<h3 id="_008_002_drop_swg">Drop</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="__drop__Intrinsic"><span class="code-inline">@drop</span> Intrinsic</h3>
<p>The <span class="code-inline">@drop</span> intrinsic calls the <span class="code-inline">opDrop</span> method if it is defined for the struct. This ensures that any necessary cleanup operations (such as freeing resources) are performed before the variable is reinitialized. <span class="code-inline">@drop</span> is particularly useful in resource management, where explicit cleanup is required before resetting the variable.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">struct</span> <span class="SCst">RGB</span>
    {
        r = <span class="SNum">1</span>, g = <span class="SNum">2</span>, b = <span class="SNum">3</span>
    }

    <span class="SKwd">var</span> rgb: [<span class="SNum">4</span>] <span class="SCst">RGB</span>

    <span class="SItr">@drop</span>(&amp;rgb, <span class="SNum">4</span>)     <span class="SCmt">// If RGB defines opDrop, it will be invoked here for each element</span>

    <span class="SItr">@init</span>(&amp;rgb, <span class="SNum">4</span>)(<span class="SNum">5</span>, <span class="SNum">6</span>, <span class="SNum">7</span>)     <span class="SCmt">// Reinitialize array elements after dropping</span>
    <span class="SItr">@assert</span>(rgb[<span class="SNum">3</span>].r == <span class="SNum">5</span>)
    <span class="SItr">@assert</span>(rgb[<span class="SNum">3</span>].g == <span class="SNum">6</span>)
    <span class="SItr">@assert</span>(rgb[<span class="SNum">3</span>].b == <span class="SNum">7</span>)
}

</span></div>
<h3 id="_008_003_value_and_type_intrinsics_swg">Value and Type Intrinsics</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Counts_and_Data_Pointers">Counts and Data Pointers</h3>
<p><span class="code-inline">@countof</span> returns the logical number of elements in a string, array, slice, enum, or type that defines <span class="code-inline">opCount</span>. <span class="code-inline">@dataof</span> returns the underlying data pointer of strings, arrays, slices, <span class="code-inline">any</span> values, and interfaces.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> values = [<span class="SNum">10</span>, <span class="SNum">20</span>, <span class="SNum">30</span>]

    <span class="SCmp">#assert</span>(<span class="SItr">@countof</span>(values) == <span class="SNum">3</span>)
    <span class="SItr">@assert</span>(<span class="SItr">@dataof</span>(values) == &amp;values[<span class="SNum">0</span>])
}

</span></div>
<h3 id="Constructing_Non-Owning_Views">Constructing Non-Owning Views</h3>
<p>'@mkslice(pointer, count)' and '@mkstring(pointer, byteCount)' pair existing storage with a length. They do not copy or retain that storage, so the result must not outlive its backing memory.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> bytes = ['<span class="SFct">S</span>'<span class="STpe">u8</span>, '<span class="SFct">w</span>'<span class="STpe">u8</span>, '<span class="SFct">a</span>'<span class="STpe">u8</span>, '<span class="SFct">g</span>'<span class="STpe">u8</span>]

    <span class="SKwd">let</span> slice = <span class="SItr">@mkslice</span>(&amp;bytes[<span class="SNum">0</span>], <span class="SItr">@countof</span>(bytes))
    <span class="SKwd">let</span> text  = <span class="SItr">@mkstring</span>(&amp;bytes[<span class="SNum">0</span>], <span class="SItr">@countof</span>(bytes))

    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(slice) == [..] <span class="STpe">u8</span>)
    <span class="SItr">@assert</span>(<span class="SItr">@countof</span>(slice) == <span class="SNum">4</span>)
    <span class="SItr">@assert</span>(text == <span class="SStr">"Swag"</span>)
}

</span></div>
<h3 id="Constructing_and_Inspecting__any_">Constructing and Inspecting <span class="code-inline">any</span></h3>
<p>Ordinary assignment boxes a value as <span class="code-inline">any</span>. <span class="code-inline">@mkany</span> is the lower-level form: it combines an address and a <span class="code-inline">typeinfo</span>. <span class="code-inline">@kindof</span> recovers the stored concrete type and <span class="code-inline">@dataof</span> recovers its address.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> value = <span class="SNum">42</span>
    <span class="SKwd">let</span> boxed = <span class="SItr">@mkany</span>(&amp;value, <span class="STpe">s32</span>)

    <span class="SItr">@assert</span>(<span class="SItr">@kindof</span>(boxed) == <span class="STpe">s32</span>)
    <span class="SItr">@assert</span>(<span class="SItr">@dataof</span>(boxed) == &amp;value)
    <span class="SItr">@assert</span>(<span class="SKwd">cast</span>(<span class="STpe">s32</span>) boxed == <span class="SNum">42</span>)
}

</span></div>
<p><span class="code-inline">@mkinterface</span> and <span class="code-inline">@tableof</span> are the corresponding low-level building blocks for interface values. Normal 'cast(MyInterface) value' syntax is safer and clearer; use the intrinsics only when implementing generic runtime machinery.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_008_004_math_and_bit_intrinsics_swg">Math and Bit Intrinsics</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Integer_Helpers">Integer Helpers</h3>
<p><span class="code-inline">@min</span>, <span class="code-inline">@max</span>, and <span class="code-inline">@abs</span> preserve the operand type. Bit intrinsics operate on unsigned widths from <span class="code-inline">u8</span> through <span class="code-inline">u64</span>.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SItr">@assert</span>(<span class="SItr">@min</span>(<span class="SNum">4</span>'<span class="STpe">s32</span>, <span class="SNum">9</span>'<span class="STpe">s32</span>) == <span class="SNum">4</span>)
    <span class="SItr">@assert</span>(<span class="SItr">@max</span>(<span class="SNum">4</span>'<span class="STpe">s32</span>, <span class="SNum">9</span>'<span class="STpe">s32</span>) == <span class="SNum">9</span>)
    <span class="SItr">@assert</span>(<span class="SItr">@abs</span>(-<span class="SNum">7</span>'<span class="STpe">s32</span>) == <span class="SNum">7</span>)

    <span class="SItr">@assert</span>(<span class="SItr">@bitcountnz</span>(<span class="SNum">0b1011</span>'<span class="STpe">u8</span>) == <span class="SNum">3</span>)
    <span class="SItr">@assert</span>(<span class="SItr">@bitcountlz</span>(<span class="SNum">1</span>'<span class="STpe">u32</span>) == <span class="SNum">31</span>)
    <span class="SItr">@assert</span>(<span class="SItr">@bitcounttz</span>(<span class="SNum">0x10</span>'<span class="STpe">u32</span>) == <span class="SNum">4</span>)
}

</span></div>
<h3 id="Byte_Order_and_Rotation">Byte Order and Rotation</h3>
<p><span class="code-inline">@byteswap</span> reverses bytes within an integer. <span class="code-inline">@rol</span> and <span class="code-inline">@ror</span> rotate bits without discarding those shifted past an edge.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">const</span> <span class="SCst">Value</span> = <span class="SNum">0x01020304</span>'<span class="STpe">u32</span>

    <span class="SItr">@assert</span>(<span class="SItr">@byteswap</span>(<span class="SCst">Value</span>) == <span class="SNum">0x04030201</span>)
    <span class="SItr">@assert</span>(<span class="SItr">@rol</span>(<span class="SNum">0x80000001</span>'<span class="STpe">u32</span>, <span class="SNum">1</span>) == <span class="SNum">0x00000003</span>)
    <span class="SItr">@assert</span>(<span class="SItr">@ror</span>(<span class="SNum">0x80000001</span>'<span class="STpe">u32</span>, <span class="SNum">1</span>) == <span class="SNum">0xC0000000</span>)
    <span class="SItr">@assert</span>(<span class="SItr">@ror</span>(<span class="SItr">@rol</span>(<span class="SCst">Value</span>, <span class="SNum">7</span>), <span class="SNum">7</span>) == <span class="SCst">Value</span>)
}

</span></div>
<h3 id="Floating-Point_Math">Floating-Point Math</h3>
<p>The compiler provides trigonometric, hyperbolic, exponential, logarithmic, and rounding operations for <span class="code-inline">f32</span> and <span class="code-inline">f64</span>. Results keep the input precision.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(<span class="SItr">@sqrt</span>(<span class="SNum">9.0</span>'<span class="STpe">f32</span>)) == <span class="STpe">f32</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(<span class="SItr">@sqrt</span>(<span class="SNum">9.0</span>'<span class="STpe">f64</span>)) == <span class="STpe">f64</span>)

    <span class="SItr">@assert</span>(<span class="SItr">@sqrt</span>(<span class="SNum">9.0</span>'<span class="STpe">f32</span>) == <span class="SNum">3.0</span>)
    <span class="SItr">@assert</span>(<span class="SItr">@pow</span>(<span class="SNum">2.0</span>'<span class="STpe">f32</span>, <span class="SNum">3.0</span>'<span class="STpe">f32</span>) == <span class="SNum">8.0</span>)
    <span class="SItr">@assert</span>(<span class="SItr">@floor</span>(<span class="SNum">3.75</span>'<span class="STpe">f32</span>) == <span class="SNum">3.0</span>)
    <span class="SItr">@assert</span>(<span class="SItr">@ceil</span>(<span class="SNum">3.25</span>'<span class="STpe">f32</span>) == <span class="SNum">4.0</span>)
    <span class="SItr">@assert</span>(<span class="SItr">@round</span>(<span class="SNum">3.5</span>'<span class="STpe">f32</span>) == <span class="SNum">4.0</span>)
    <span class="SItr">@assert</span>(<span class="SItr">@sin</span>(<span class="SNum">0.0</span>'<span class="STpe">f32</span>) == <span class="SNum">0.0</span>)
}

</span></div>
<p>The complete family is indexed in the keyword chapter. Domain checks such as a negative square root depend on the active safety and sanity configuration.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_008_005_memory_and_atomic_intrinsics_swg">Memory and Atomic Intrinsics</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Raw_Memory">Raw Memory</h3>
<p><span class="code-inline">@memcpy</span> copies non-overlapping bytes, <span class="code-inline">@memmove</span> supports overlap, <span class="code-inline">@memset</span> writes one byte value repeatedly, and <span class="code-inline">@memcmp</span> compares byte sequences. Counts are expressed in bytes.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> source      = [<span class="SNum">1</span>'<span class="STpe">u8</span>, <span class="SNum">2</span>, <span class="SNum">3</span>, <span class="SNum">4</span>]
    <span class="SKwd">var</span> destination = [<span class="SNum">0</span>'<span class="STpe">u8</span>, <span class="SNum">0</span>, <span class="SNum">0</span>, <span class="SNum">0</span>]

    <span class="SItr">@memcpy</span>(&amp;destination[<span class="SNum">0</span>], &amp;source[<span class="SNum">0</span>], <span class="SItr">@countof</span>(source))
    <span class="SItr">@assert</span>(<span class="SItr">@memcmp</span>(&amp;destination[<span class="SNum">0</span>], &amp;source[<span class="SNum">0</span>], <span class="SItr">@countof</span>(source)) == <span class="SNum">0</span>)

    <span class="SItr">@memmove</span>(&amp;destination[<span class="SNum">1</span>], &amp;destination[<span class="SNum">0</span>], <span class="SNum">3</span>)
    <span class="SItr">@assert</span>(destination[<span class="SNum">0</span>] == <span class="SNum">1</span> <span class="SLgc">and</span> destination[<span class="SNum">1</span>] == <span class="SNum">1</span>)
    <span class="SItr">@assert</span>(destination[<span class="SNum">2</span>] == <span class="SNum">2</span> <span class="SLgc">and</span> destination[<span class="SNum">3</span>] == <span class="SNum">3</span>)

    <span class="SItr">@memset</span>(&amp;destination[<span class="SNum">0</span>], <span class="SNum">0</span>'<span class="STpe">u8</span>, <span class="SItr">@countof</span>(destination))
    <span class="SItr">@assert</span>(destination[<span class="SNum">0</span>] == <span class="SNum">0</span> <span class="SLgc">and</span> destination[<span class="SNum">1</span>] == <span class="SNum">0</span>)
    <span class="SItr">@assert</span>(destination[<span class="SNum">2</span>] == <span class="SNum">0</span> <span class="SLgc">and</span> destination[<span class="SNum">3</span>] == <span class="SNum">0</span>)
}

</span></div>
<h3 id="Allocation">Allocation</h3>
<p><span class="code-inline">@alloc</span> returns nullable raw storage, <span class="code-inline">@realloc</span> resizes an allocation, and <span class="code-inline">@free</span> releases it. Cast the result to the intended pointer type, prove it non-null before use, and pair every successful allocation with <span class="code-inline">@free</span>.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> data = <span class="SKwd">cast</span>(<span class="SItr">#null</span> [*] <span class="STpe">u32</span>) <span class="SItr">@alloc</span>(<span class="SNum">4</span> * <span class="SItr">#sizeof</span>(<span class="STpe">u32</span>))
    <span class="SLgc">if</span> data == <span class="SKwd">null</span> <span class="SLgc">do</span>
        <span class="SLgc">unreachable</span>

    <span class="SKwd">let</span> usable = <span class="SKwd">notnull</span> data
    <span class="SLgc">defer</span> <span class="SItr">@free</span>(usable)

    usable[<span class="SNum">0</span>] = <span class="SNum">10</span>
    usable[<span class="SNum">3</span>] = <span class="SNum">40</span>
    <span class="SItr">@assert</span>(usable[<span class="SNum">0</span>] + usable[<span class="SNum">3</span>] == <span class="SNum">50</span>)
}

</span></div>
<h3 id="Atomic_Read-Modify-Write">Atomic Read-Modify-Write</h3>
<p>Atomic intrinsics update an integer through a pointer and return its <b>previous</b> value. The family includes add, bitwise and/or/xor, exchange, and compare- exchange.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> counter = <span class="SNum">10</span>'<span class="STpe">s32</span>

    <span class="SKwd">let</span> beforeAdd = <span class="SItr">@atomadd</span>(&amp;counter, <span class="SNum">5</span>)
    <span class="SItr">@assert</span>(beforeAdd == <span class="SNum">10</span> <span class="SLgc">and</span> counter == <span class="SNum">15</span>)

    <span class="SKwd">let</span> beforeExchange = <span class="SItr">@atomxchg</span>(&amp;counter, <span class="SNum">20</span>)
    <span class="SItr">@assert</span>(beforeExchange == <span class="SNum">15</span> <span class="SLgc">and</span> counter == <span class="SNum">20</span>)

    <span class="SKwd">let</span> beforeCompareExchange = <span class="SItr">@atomcmpxchg</span>(&amp;counter, <span class="SNum">20</span>, <span class="SNum">30</span>)
    <span class="SItr">@assert</span>(beforeCompareExchange == <span class="SNum">20</span> <span class="SLgc">and</span> counter == <span class="SNum">30</span>)
}

</span></div>
<div class="blockquote blockquote-warning">
<div class="blockquote-title-block"><span class="blockquote-title">Warning</span></div>
<p>Raw memory operations bypass <span class="code-inline">opPostCopy</span>, <span class="code-inline">opPostMove</span>, and <span class="code-inline">opDrop</span>. Do not use them to copy or relocate lifecycle-bearing values unless the type's invariants explicitly permit it.</p>
</div>
<div class="code-block"><span class="SCde">
</span></div>
<h2 id="_009_000_generics_swg">Generics</h2>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>
</span></div>
<p>Generics accept types and compile-time values. Swag specializes a generic when it is used, then applies <span class="code-inline">where</span> constraints to decide whether the candidate is valid. Prefer constraints that describe required capabilities rather than testing a concrete type name.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_009_001_functions_swg">Functions</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Generic_Functions">Generic Functions</h3>
<p>Generic parameters appear between <span class="code-inline">func</span> and the function name. 'var T' declares a type parameter; 'const N: s32' declares a compile-time value parameter.</p>
<p>The compiler normally deduces type parameters from call arguments:</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">func</span>(<span class="SKwd">var</span> <span class="SCst">T</span>) <span class="SFct">genericTwice</span>(value: <span class="SCst">T</span>)-&gt;<span class="SCst">T</span>
{
    <span class="SLgc">return</span> value + value
}

<span class="SFct">#test</span>
{
    <span class="SItr">@assert</span>(<span class="SFct">genericTwice</span>(<span class="SNum">21</span>'<span class="STpe">s32</span>) == <span class="SNum">42</span>)
    <span class="SItr">@assert</span>(<span class="SFct">genericTwice</span>(<span class="SNum">1.5</span>'<span class="STpe">f32</span>) == <span class="SNum">3.0</span>'<span class="STpe">f32</span>)

    <span class="SCmt">// An apostrophe supplies generic arguments explicitly.</span>
    <span class="SItr">@assert</span>(<span class="SFct">genericTwice</span>'<span class="STpe">s64</span>(<span class="SNum">12</span>) == <span class="SNum">24</span>)
}

</span></div>
<h3 id="Multiple_and_Explicit_Arguments">Multiple and Explicit Arguments</h3>
<p>Use parentheses after the apostrophe when a specialization has more than one generic argument.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">func</span>(<span class="SKwd">var</span> <span class="SCst">Key</span>, <span class="SKwd">var</span> <span class="SCst">Value</span>) <span class="SFct">genericSelect</span>(key: <span class="SCst">Key</span>, value: <span class="SCst">Value</span>)-&gt;<span class="SCst">Value</span>
{
    <span class="SKwd">discard</span> key
    <span class="SLgc">return</span> value
}

<span class="SFct">#test</span>
{
    <span class="SItr">@assert</span>(<span class="SFct">genericSelect</span>(<span class="SNum">7</span>'<span class="STpe">u32</span>, <span class="SStr">"seven"</span>) == <span class="SStr">"seven"</span>)
    <span class="SItr">@assert</span>(<span class="SFct">genericSelect</span>'(<span class="STpe">u32</span>, <span class="STpe">bool</span>)(<span class="SNum">7</span>, <span class="SKwd">true</span>))
}

</span></div>
<h3 id="Defaults">Defaults</h3>
<p>A generic default is used when deduction and explicit arguments do not provide that parameter.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">func</span>(<span class="SKwd">var</span> <span class="SCst">T</span> = <span class="STpe">s32</span>) <span class="SFct">genericZero</span>()-&gt;<span class="SCst">T</span>
{
    <span class="SLgc">return</span> <span class="SNum">0</span>
}

<span class="SFct">#test</span>
{
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(<span class="SFct">genericZero</span>()) == <span class="STpe">s32</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(<span class="SFct">genericZero</span>'<span class="STpe">f64</span>()) == <span class="STpe">f64</span>)
    <span class="SItr">@assert</span>(<span class="SFct">genericZero</span>'<span class="STpe">f64</span>() == <span class="SNum">0.0</span>'<span class="STpe">f64</span>)
}

</span></div>
<h3 id="Compile-Time_Value_Parameters">Compile-Time Value Parameters</h3>
<p>Value parameters can shape types and declarations. They are constants inside the specialization.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">func</span>(<span class="SKwd">var</span> <span class="SCst">T</span>, <span class="SKwd">const</span> <span class="SCst">Count</span>: <span class="STpe">s32</span>) <span class="SFct">genericRepeat</span>(value: <span class="SCst">T</span>)-&gt;[<span class="SCst">Count</span>] <span class="SCst">T</span>
    <span class="SLgc">where</span> <span class="SCst">Count</span> &gt;= <span class="SNum">0</span>
{
    <span class="SKwd">var</span> result: [<span class="SCst">Count</span>] <span class="SCst">T</span>
    <span class="SLgc">for</span> [index] <span class="SLgc">in</span> <span class="SCst">Count</span> <span class="SLgc">do</span>
        result[index] = value
    <span class="SLgc">return</span> result
}

<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> values = <span class="SFct">genericRepeat</span>'(<span class="STpe">s32</span>, <span class="SNum">3</span>)(<span class="SNum">9</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(values) == <span class="SItr">#type</span> [<span class="SNum">3</span>] <span class="STpe">s32</span>)
    <span class="SItr">@assert</span>(values[<span class="SNum">0</span>] == <span class="SNum">9</span> <span class="SLgc">and</span> values[<span class="SNum">1</span>] == <span class="SNum">9</span> <span class="SLgc">and</span> values[<span class="SNum">2</span>] == <span class="SNum">9</span>)
}

</span></div>
<p>When the role is unambiguous, Swag also accepts the shorter forms <span class="code-inline">T</span> for a type parameter and 'N: s32' for a value parameter. Both spellings mean the same thing; this reference uses the explicit <span class="code-inline">var</span> and <span class="code-inline">const</span> forms wherever it states a contract, and the short form in introductory examples.</p>
<h3 id="Specialization_Aliases">Specialization Aliases</h3>
<p>An alias can capture some or all generic arguments:</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">alias</span> <span class="SCst">RepeatFourBytes</span> = <span class="SFct">genericRepeat</span>'(<span class="STpe">u8</span>, <span class="SNum">4</span>)

<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> bytes = <span class="SFct">RepeatFourBytes</span>(<span class="SNum">0xA5</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(bytes) == <span class="SItr">#type</span> [<span class="SNum">4</span>] <span class="STpe">u8</span>)
    <span class="SItr">@assert</span>(bytes[<span class="SNum">3</span>] == <span class="SNum">0xA5</span>)
}

</span></div>
<p>A specialization is compiled when used. Its body must be valid for the selected arguments; use <span class="code-inline">where</span> constraints to exclude unsupported candidates with a clear overload contract.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_009_002_structs_swg">Structs</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Generic_Structs">Generic Structs</h3>
<p>A generic struct uses the same parameter syntax as a generic function. Each specialization is a distinct type with its own layout.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">struct</span>(<span class="SKwd">var</span> <span class="SCst">T</span>) <span class="SCst">GenericBox</span>
{
    value: <span class="SCst">T</span>
}

<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> integer = <span class="SFct">GenericBox</span>'<span class="STpe">s32</span>{value: <span class="SNum">42</span>}
    <span class="SKwd">let</span> text    = <span class="SFct">GenericBox</span>'<span class="STpe">string</span>{value: <span class="SStr">"answer"</span>}

    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(integer) == <span class="SFct">GenericBox</span>'<span class="STpe">s32</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(integer.value) == <span class="STpe">s32</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(text.value) == <span class="STpe">string</span>)
    <span class="SItr">@assert</span>(integer.value == <span class="SNum">42</span>)
    <span class="SItr">@assert</span>(text.value == <span class="SStr">"answer"</span>)
}

</span></div>
<h3 id="Type_and_Value_Parameters">Type and Value Parameters</h3>
<p>Compile-time values can determine field types and array dimensions.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">struct</span>(<span class="SKwd">var</span> <span class="SCst">T</span>, <span class="SKwd">const</span> <span class="SCst">Count</span>: <span class="STpe">s32</span>) <span class="SCst">GenericBuffer</span>
    <span class="SLgc">where</span> <span class="SCst">Count</span> &gt; <span class="SNum">0</span>
{
    values: [<span class="SCst">Count</span>] <span class="SCst">T</span>
}

<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> flags: <span class="SFct">GenericBuffer</span>'(<span class="STpe">bool</span>, <span class="SNum">3</span>) = {values: [<span class="SKwd">true</span>, <span class="SKwd">false</span>, <span class="SKwd">true</span>]}

    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(flags.values) == <span class="SItr">#type</span> [<span class="SNum">3</span>] <span class="STpe">bool</span>)
    <span class="SItr">@assert</span>(flags.values[<span class="SNum">0</span>] <span class="SLgc">and</span> !flags.values[<span class="SNum">1</span>] <span class="SLgc">and</span> flags.values[<span class="SNum">2</span>])
}

</span></div>
<h3 id="Generic_Methods">Generic Methods</h3>
<p>An <span class="code-inline">impl</span> for a generic struct sees the struct's parameters. Methods can add their own generic parameters.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">impl</span> <span class="SCst">GenericBox</span>
{
    <span class="SKwd">mtd</span> <span class="SKwd">const</span> <span class="SFct">get</span>()-&gt;<span class="SCst">T</span>
    {
        <span class="SLgc">return</span> .value
    }

    <span class="SKwd">func</span>(<span class="SKwd">var</span> <span class="SCst">U</span>) <span class="SFct">pair</span>(<span class="SKwd">const</span> <span class="STpe">me</span>, other: <span class="SCst">U</span>)-&gt;{first: <span class="SCst">T</span>, second: <span class="SCst">U</span>}
    {
        <span class="SLgc">return</span> {first: <span class="STpe">me</span>.value, second: other}
    }
}

<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> box  = <span class="SFct">GenericBox</span>'<span class="STpe">u16</span>{value: <span class="SNum">12</span>}
    <span class="SKwd">let</span> pair = box.<span class="SFct">pair</span>(<span class="SStr">"items"</span>)

    <span class="SItr">@assert</span>(box.<span class="SFct">get</span>() == <span class="SNum">12</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(pair.first) == <span class="STpe">u16</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(pair.second) == <span class="STpe">string</span>)
    <span class="SItr">@assert</span>(pair.second == <span class="SStr">"items"</span>)
}

</span></div>
<p>Use a default when one specialization is the natural choice:</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">struct</span>(<span class="SKwd">var</span> <span class="SCst">T</span> = <span class="STpe">s32</span>) <span class="SCst">GenericCounter</span>
{
    value: <span class="SCst">T</span>
}

<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> defaultCounter: <span class="SCst">GenericCounter</span>     = {value: <span class="SNum">1</span>}
    <span class="SKwd">let</span> wideCounter:    <span class="SFct">GenericCounter</span>'<span class="STpe">u64</span> = {value: <span class="SNum">2</span>}

    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(defaultCounter.value) == <span class="STpe">s32</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(wideCounter.value) == <span class="STpe">u64</span>)
}

</span></div>
<h3 id="_009_003_where_constraints_swg">Where Constraints</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Generic__where__Constraints">Generic <span class="code-inline">where</span> Constraints</h3>
<p>The <span class="code-inline">where</span> clause constrains generic functions and generic structs. It is evaluated at compile time from generic parameters and other constant data.</p>
<p>For functions, a failing <span class="code-inline">where</span> removes that specialization from overload resolution. For generic structs, a failing <span class="code-inline">where</span> prevents the instantiation entirely because structs do not participate in overload selection.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="Function_Specialization">Function Specialization</h3>
<p>Different overloads can share the same generic signature and still be selected by different <span class="code-inline">where</span> clauses.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">func</span>(<span class="SCst">T</span>) <span class="SFct">classify</span>(value: <span class="SCst">T</span>)-&gt;<span class="STpe">u8</span>
        <span class="SLgc">where</span> <span class="SCst">T</span> == <span class="STpe">s32</span> <span class="SLgc">or</span> <span class="SCst">T</span> == <span class="STpe">s64</span>
    {
        <span class="SLgc">return</span> <span class="SNum">1</span>
    }

    <span class="SKwd">func</span>(<span class="SCst">T</span>) <span class="SFct">classify</span>(value: <span class="SCst">T</span>)-&gt;<span class="STpe">u8</span>
        <span class="SLgc">where</span> <span class="SCst">T</span> == <span class="STpe">f32</span> <span class="SLgc">or</span> <span class="SCst">T</span> == <span class="STpe">f64</span>
    {
        <span class="SLgc">return</span> <span class="SNum">2</span>
    }

    <span class="SItr">@assert</span>(<span class="SFct">classify</span>(<span class="SNum">1</span>'<span class="STpe">s32</span>) == <span class="SNum">1</span>)
    <span class="SItr">@assert</span>(<span class="SFct">classify</span>(<span class="SNum">1.5</span>'<span class="STpe">f32</span>) == <span class="SNum">2</span>)
}

</span></div>
<h3 id="Block-based_Constraints">Block-based Constraints</h3>
<p><span class="code-inline">where</span> can also be a block returning a compile-time <span class="code-inline">bool</span>. This is useful when the constraint is clearer as ordinary control flow.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">func</span>(<span class="SCst">T</span>, <span class="SCst">U</span> = <span class="SCst">T</span>) <span class="SFct">sameTypePair</span>(left: <span class="SCst">T</span>, right: <span class="SCst">U</span>)-&gt;<span class="SCst">U</span>
        <span class="SLgc">where</span>
        {
            <span class="SLgc">if</span> <span class="SCst">T</span> == <span class="SCst">U</span> <span class="SLgc">do</span>
                <span class="SLgc">return</span> <span class="SKwd">true</span>
            <span class="SLgc">return</span> <span class="SKwd">false</span>
        }
    {
        <span class="SLgc">return</span> right
    }

    <span class="SItr">@assert</span>(<span class="SFct">sameTypePair</span>(<span class="SNum">10</span>'<span class="STpe">s32</span>, <span class="SNum">20</span>'<span class="STpe">s32</span>) == <span class="SNum">20</span>)
    <span class="SItr">@assert</span>(<span class="SFct">sameTypePair</span>'(<span class="STpe">f64</span>)(<span class="SNum">1.0</span>'<span class="STpe">f64</span>, <span class="SNum">2.0</span>'<span class="STpe">f64</span>) == <span class="SNum">2.0</span>'<span class="STpe">f64</span>)
}

</span></div>
<h3 id="Generic_Struct_Constraints">Generic Struct Constraints</h3>
<p>Generic structs can also be constrained. The condition is checked as soon as the compiler tries to instantiate the type.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">struct</span>(<span class="SCst">T</span> = <span class="STpe">f64</span>) <span class="SCst">FloatPoint</span>
        <span class="SLgc">where</span> <span class="SCst">T</span> == <span class="STpe">f32</span> <span class="SLgc">or</span> <span class="SCst">T</span> == <span class="STpe">f64</span>
    {
        x, y: <span class="SCst">T</span>
    }

    <span class="SKwd">struct</span>(<span class="SCst">T</span>, <span class="SCst">Rows</span>: <span class="STpe">s32</span>, <span class="SCst">Cols</span>: <span class="STpe">s32</span> = <span class="SCst">Rows</span>) <span class="SCst">SquareMatrix</span>
        <span class="SLgc">where</span> <span class="SCst">Rows</span> &gt; <span class="SNum">0</span>
        <span class="SLgc">where</span> <span class="SCst">Cols</span> &gt; <span class="SNum">0</span>
        <span class="SLgc">where</span> <span class="SCst">Rows</span> == <span class="SCst">Cols</span>
        <span class="SLgc">where</span> <span class="SCst">T</span> == <span class="STpe">f32</span> <span class="SLgc">or</span> <span class="SCst">T</span> == <span class="STpe">f64</span>
    {
        data: [<span class="SCst">Rows</span> * <span class="SCst">Cols</span>] <span class="SCst">T</span>
    }

    <span class="SKwd">let</span> point:  <span class="SFct">FloatPoint</span>'<span class="STpe">f64</span>        = {x: <span class="SNum">1.5</span>, y: <span class="SNum">2.5</span>}
    <span class="SKwd">let</span> matrix: <span class="SFct">SquareMatrix</span>'(<span class="STpe">f32</span>, <span class="SNum">2</span>) = {data: [<span class="SNum">1.0</span>'<span class="STpe">f32</span>, <span class="SNum">2.0</span>, <span class="SNum">3.0</span>, <span class="SNum">4.0</span>]}

    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(point.x) == <span class="STpe">f64</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(matrix.data) == <span class="SItr">#type</span> [<span class="SNum">4</span>] <span class="STpe">f32</span>)
}

</span></div>
<h3 id="Generic_Methods_with_Inherited_Arguments">Generic Methods with Inherited Arguments</h3>
<p>Method constraints can use a method's own generic parameters together with the generic arguments inherited from the surrounding generic struct instance.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">struct</span>(<span class="SCst">T</span>, <span class="SCst">Count</span>: <span class="STpe">s32</span>) <span class="SCst">RefWindow</span>
{
    values: [<span class="SCst">Count</span>] <span class="SCst">T</span>
}

<span class="SKwd">impl</span> <span class="SCst">RefWindow</span>
{
    <span class="SKwd">func</span>(<span class="SKwd">const</span> <span class="SCst">Index</span>: <span class="STpe">s32</span>) <span class="SFct">at</span>(<span class="SKwd">const</span> <span class="STpe">me</span>)-&gt;<span class="SCst">T</span>
        <span class="SLgc">where</span> <span class="SCst">Index</span> &gt;= <span class="SNum">0</span>
        <span class="SLgc">where</span> <span class="SCst">Index</span> &lt; <span class="SCst">Count</span>
    {
        <span class="SLgc">return</span> <span class="STpe">me</span>.values[<span class="SCst">Index</span>]
    }

    <span class="SKwd">func</span>(<span class="SCst">U</span> = <span class="SCst">T</span>) <span class="SFct">sameSample</span>(<span class="SKwd">const</span> <span class="STpe">me</span>, other: <span class="SCst">U</span>)-&gt;<span class="SCst">U</span>
        <span class="SLgc">where</span> <span class="SCst">Count</span> &gt; <span class="SNum">0</span>
        <span class="SLgc">where</span> <span class="SCst">T</span> == <span class="SCst">U</span>
    {
        <span class="SLgc">return</span> other
    }
}

<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> floatWindow: <span class="SFct">RefWindow</span>'(<span class="STpe">f32</span>, <span class="SNum">3</span>) = {values: [<span class="SNum">10.0</span>'<span class="STpe">f32</span>, <span class="SNum">20.0</span>, <span class="SNum">30.0</span>]}

    <span class="SItr">@assert</span>(floatWindow.<span class="SFct">at</span>'<span class="SNum">1</span>() == <span class="SNum">20.0</span>'<span class="STpe">f32</span>)
    <span class="SItr">@assert</span>(floatWindow.<span class="SFct">sameSample</span>(<span class="SNum">99.0</span>'<span class="STpe">f32</span>) == <span class="SNum">99.0</span>'<span class="STpe">f32</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(floatWindow.<span class="SFct">sameSample</span>(<span class="SNum">1.5</span>'<span class="STpe">f32</span>)) == <span class="STpe">f32</span>)
}

</span></div>
<h2 id="_010_000_attributes_swg">Attributes</h2>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>
</span></div>
<p>Attributes attach structured metadata to declarations and to lexical scopes. User attributes support reflection and metaprogramming; predefined <span class="code-inline">Swag</span> attributes also control compiler behavior such as layout, safety, code generation, and native interoperability.</p>
<p>An attribute annotates something that has a symbol. Everything without one — a type, an operand, a conversion, a literal, a statement — takes a <span class="code-inline">#</span> modifier instead. See the sigils chapter for the rule and its consequences.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_010_001_user_attributes_swg">User Attributes</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="User_Attributes">User Attributes</h3>
<p>Attributes in Swag let you annotate code elements (functions, structs, etc.) with metadata. These annotations, defined with the <span class="code-inline">attr</span> keyword, can power code generation and reflection. By attaching attributes, you enrich code with extra information usable at compile time and at runtime.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">using</span> <span class="SCst">Swag</span>

<span class="SKwd">attr</span> <span class="SFct">AttributeA</span>()

<span class="SCmt">// Simple attribute without parameters</span>

</span></div>
<h3 id="Attributes_with_Parameters">Attributes with Parameters</h3>
<p>Attributes can accept parameters, similar to functions. Parameters let you customize how the attribute configures the annotated element.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">attr</span> <span class="SFct">AttributeB</span>(x, y: <span class="STpe">s32</span>, z: <span class="STpe">string</span>)

<span class="SCmt">// Attribute with multiple parameters</span>

</span></div>
<h3 id="Attributes_with_Default_Values">Attributes with Default Values</h3>
<p>Attributes may define default parameter values. When applied, omitted arguments fall back to their defaults.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">attr</span> <span class="SFct">AttributeBA</span>(x: <span class="STpe">s32</span>, y: <span class="STpe">string</span> = <span class="SStr">"string"</span>)

<span class="SCmt">// Attribute with a defaulted parameter</span>

</span></div>
<h3 id="Restricting_Attribute_Usage">Restricting Attribute Usage</h3>
<p>Use the <span class="code-inline">AttrUsage</span> specifier to control where an attribute may be applied (e.g., function-only, struct-only). The compiler rejects the attribute on any other declaration kind. An attribute that declares no <span class="code-inline">AttrUsage</span> is accepted everywhere.</p>
<div class="code-block"><span class="SCde"><span class="SAtr">#[AttrUsage(AttributeUsage.Function)]</span>
<span class="SKwd">attr</span> <span class="SFct">AttributeC</span>()

<span class="SCmt">// Restricted to function usage</span>

</span></div>
<h3 id="Scopes_and_Broadcasting">Scopes and Broadcasting</h3>
<p>An attribute written on a block applies to every declaration the block contains, and each of those declarations is checked against <span class="code-inline">AttrUsage</span> separately. A declaration the attribute does not accept simply does not receive it, so one block can carry an attribute meant for only some of its members.</p>
<p><span class="code-inline">AttributeUsage.Scope</span> marks an attribute that acts on the lexical scope itself instead of on a declaration; <span class="code-inline">Swag.Safety</span>, <span class="code-inline">Swag.Sanity</span>, <span class="code-inline">Swag.Warning</span>, and <span class="code-inline">Swag.Optimize</span> are the predefined ones.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="Applying_Attributes">Applying Attributes</h3>
<p>Apply attributes with the syntax '#[attribute, attribute...]' placed immediately before the code element. Multiple attributes are comma-separated.</p>
<div class="code-block"><span class="SCde"><span class="SAtr">#[AttributeA, AttributeB(0, 0, "string")]</span>
<span class="SKwd">func</span> <span class="SFct">function1</span>()
{
<span class="SCmt">// Function annotated with multiple attributes</span>
}

</span></div>
<h3 id="Multiple_Usages">Multiple Usages</h3>
<p>An attribute can target several element kinds by combining <span class="code-inline">AttrUsage</span> flags with a bitwise OR. This enables reuse across contexts (e.g., functions, structs).</p>
<div class="code-block"><span class="SCde"><span class="SAtr">#[AttrUsage(AttributeUsage.Function | AttributeUsage.Struct)]</span>
<span class="SKwd">attr</span> <span class="SFct">AttributeD</span>(x: <span class="STpe">s32</span>)

<span class="SCmt">// Applicable to both functions and structs</span>

<span class="SAtr">#[AttributeD(6)]</span>
<span class="SKwd">func</span> <span class="SFct">function2</span>()
{
<span class="SCmt">// Function annotated with a multi-usage attribute</span>
}

<span class="SAtr">#[AttributeD(150)]</span>
<span class="SKwd">struct</span> struct1
{
<span class="SCmt">// Struct annotated with the same attribute</span>
}

</span></div>
<h3 id="Retrieving_Attributes_at_Runtime">Retrieving Attributes at Runtime</h3>
<p>You can inspect attributes via type reflection at runtime. This enables behavior that adapts based on which attributes are present and how they are configured.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> type = <span class="SKwd">cast</span>(<span class="SKwd">const</span> *<span class="SCst">Swag</span>.<span class="SCst">TypeInfoFunc</span>) <span class="SItr">#typeof</span>(function2)     <span class="SCmt">// Reflect the function type</span>
    <span class="SItr">@assert</span>(<span class="SItr">@countof</span>(type.attributes) == <span class="SNum">1</span>)                          <span class="SCmt">// Exactly one attribute on 'function2'</span>
}

</span></div>
<h3 id="_010_002_predefined_attributes_swg">Predefined Attributes</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>
</span></div>
<h3 id="Predefined_Attributes">Predefined Attributes</h3>
<p>The compiler runtime exports predefined attributes in the <span class="code-inline">Swag</span> namespace. This page follows the API shipped in <span class="code-inline">bin/runtime/api.swg</span>; it is the compact index, while the relevant language chapters demonstrate the attributes that change everyday program behavior.</p>
<h3 id="Declaring_Attributes">Declaring Attributes</h3>
<table class="table-markdown">
<tr><th>Attribute</th><th>Purpose</th></tr>
<tr><td><span class="code-inline">AttrUsage(usage)</span></td><td>Restrict the kinds of declarations an attribute accepts</td></tr>
<tr><td><span class="code-inline">AttrMulti()</span></td><td>Allow the same attribute to appear more than once</td></tr>
</table>
<p><span class="code-inline">Swag.AttributeUsage</span> is a flag enum. Combine values such as <span class="code-inline">.Function</span>, <span class="code-inline">.Struct</span>, <span class="code-inline">.Enum</span>, <span class="code-inline">.Alias</span>, and <span class="code-inline">.Variable</span> with <span class="code-inline">|</span>. <span class="code-inline">.Scope</span> marks an attribute that acts on a lexical scope instead of a declaration, and <span class="code-inline">.File</span> one that can be written with <span class="code-inline">#global</span>.</p>
<p>The compiler enforces the declared usage: writing an attribute directly on another kind of declaration is an error. An attribute with no <span class="code-inline">AttrUsage</span> is unrestricted.</p>
<h3 id="Name_Resolution">Name Resolution</h3>
<table class="table-markdown">
<tr><th>Attribute</th><th>Purpose</th></tr>
<tr><td>'Using(what: typeinfo...)'</td><td>Bring the named scopes into the annotated declaration's scope</td></tr>
</table>
<p><span class="code-inline">Swag.Using</span> is the attribute form of the <span class="code-inline">using</span> statement: it opens the named namespaces or types inside the declaration it annotates, so their members resolve unqualified there. Annotating a struct with it is the usual way to let field attributes be written unqualified:</p>
<div class="code-block"><span class="SCde"><span class="SAtr">#[Swag.Using(Properties)]</span>
<span class="SKwd">struct</span> <span class="SCst">CaptureOptions</span>
{
    <span class="SAtr">#[Description("Show a large cross at the mouse position")]</span>
    drawCross = <span class="SKwd">true</span>
}
</span></div>
<p>This one is declared in <span class="code-inline">bin/runtime/core.swg</span> rather than <span class="code-inline">api.swg</span>, because it needs <span class="code-inline">typeinfo</span> and cannot exist in the bootstrap.</p>
<h3 id="Compile-Time_Execution_and_Code_Generation">Compile-Time Execution and Code Generation</h3>
<table class="table-markdown">
<tr><th>Attribute</th><th>Purpose</th></tr>
<tr><td><span class="code-inline">ConstExpr()</span></td><td>Allow a function or struct operation to run in a constant expression</td></tr>
<tr><td><span class="code-inline">Compiler()</span></td><td>Keep a function, global, or constant in the compile-time environment</td></tr>
<tr><td>'PrintAst(stages: string...)'</td><td>Print the selected declaration's AST for compiler diagnostics</td></tr>
<tr><td>'PrintMicro(stages: string...)'</td><td>Print generated Micro IR at selected pipeline stages</td></tr>
<tr><td><span class="code-inline">Inline()</span></td><td>Require inlining</td></tr>
<tr><td><span class="code-inline">NoInline()</span></td><td>Ask the backend not to inline</td></tr>
<tr><td><span class="code-inline">PlaceHolder()</span></td><td>Generate an empty function body</td></tr>
<tr><td><span class="code-inline">NoPrint()</span></td><td>Disable <span class="code-inline">@print</span> in the annotated function</td></tr>
<tr><td>'Optimize(level: bool)'</td><td>Enable or disable optimized code generation</td></tr>
</table>
<p><span class="code-inline">PrintAst</span> and <span class="code-inline">PrintMicro</span> are development aids: they write compiler output and should not be used for program logic.</p>
<h3 id="Metaprogramming_and_Call_Semantics">Metaprogramming and Call Semantics</h3>
<table class="table-markdown">
<tr><th>Attribute</th><th>Purpose</th></tr>
<tr><td><span class="code-inline">Macro()</span></td><td>Inline a function while preserving the caller's expression context</td></tr>
<tr><td><span class="code-inline">Mixin()</span></td><td>Inject declarations or statements at the call site</td></tr>
<tr><td><span class="code-inline">CalleeReturn()</span></td><td>Make <span class="code-inline">return</span> in a macro or mixin return from the caller</td></tr>
<tr><td><span class="code-inline">Implicit()</span></td><td>Permit an <span class="code-inline">opCast</span> overload as an implicit conversion</td></tr>
<tr><td><span class="code-inline">Discardable()</span></td><td>Permit a function result to be ignored</td></tr>
<tr><td>'Deprecated(msg: #null string = null)'</td><td>Mark an API as deprecated</td></tr>
</table>
<h3 id="Operators__Matching__and_Enums">Operators, Matching, and Enums</h3>
<table class="table-markdown">
<tr><th>Attribute</th><th>Purpose</th></tr>
<tr><td>'Operators(operators: string...)'</td><td>Generate selected structural operators</td></tr>
<tr><td><span class="code-inline">OperatorIgnore()</span></td><td>Exclude one field from generated operators</td></tr>
<tr><td>'Commutative(operators: Operator...)'</td><td>Allow selected binary overloads with the receiver on the right</td></tr>
<tr><td><span class="code-inline">FullInit()</span></td><td>Declare that an <span class="code-inline">opSet</span> or <span class="code-inline">opCast</span> initializes the whole destination</td></tr>
<tr><td><span class="code-inline">Incomplete()</span></td><td>Document that an enum's declared values are not the full set</td></tr>
<tr><td><span class="code-inline">EnumFlags()</span></td><td>Define an enum whose values form a bit mask</td></tr>
<tr><td><span class="code-inline">NoDuplicate()</span></td><td>Reject duplicate enum values</td></tr>
<tr><td>'Match(what: MatchWhat, value: bool)'</td><td>Adjust compiler overload-matching rules</td></tr>
</table>
<p>Exhaustive matching is not an attribute: a <span class="code-inline">switch</span> carries no symbol, so it is requested with the 'switch #complete' modifier.</p>
<p><span class="code-inline">Swag.Match</span> is a low-level compiler contract. Application code should normally express overload selection with types and <span class="code-inline">where</span> constraints.</p>
<h3 id="Layout__Ownership__and_Export">Layout, Ownership, and Export</h3>
<table class="table-markdown">
<tr><th>Attribute</th><th>Purpose</th></tr>
<tr><td>'Align(value: u8)'</td><td>Override alignment for a field or aggregate</td></tr>
<tr><td>'Pack(value: u8)'</td><td>Set struct packing</td></tr>
<tr><td>'Offset(name: string)'</td><td>Overlay a field on another named field</td></tr>
<tr><td><span class="code-inline">NoCopy()</span></td><td>Forbid copying a struct</td></tr>
<tr><td><span class="code-inline">Opaque()</span></td><td>Hide a struct's contents from exported module APIs</td></tr>
<tr><td>'ExportType(what: ExportWhat)'</td><td>Export selected runtime reflection data</td></tr>
<tr><td><span class="code-inline">Tls()</span></td><td>Give each thread its own instance of a global</td></tr>
<tr><td><span class="code-inline">Global()</span></td><td>Give a local declaration static storage</td></tr>
<tr><td><span class="code-inline">Late()</span></td><td>Defer the initialization of a non-null field or global</td></tr>
<tr><td><span class="code-inline">Strict()</span></td><td>Keep an alias distinct for implicit-conversion purposes</td></tr>
</table>
<p><span class="code-inline">Swag.ExportWhat</span> currently provides <span class="code-inline">.Methods</span> and <span class="code-inline">.NoZero</span> flags, plus <span class="code-inline">.None</span> and <span class="code-inline">.All</span>. Exporting methods makes <span class="code-inline">TypeInfoStruct.methods</span> available; it does not make a private method public in source code.</p>
<h3 id="Safety_and_Diagnostics">Safety and Diagnostics</h3>
<table class="table-markdown">
<tr><th>Attribute</th><th>Purpose</th></tr>
<tr><td>'Safety(what: SafetyWhat, value: bool)'</td><td>Enable or disable runtime guards</td></tr>
<tr><td>'Sanity(what: SafetyWhat, value: bool)'</td><td>Enable or disable static proven-fault checks</td></tr>
<tr><td>'Warning(what: string, level: WarningLevel)'</td><td>Enable, disable, or promote diagnostic IDs</td></tr>
<tr><td>'BorrowSummary(returns, stores = 0, into = 0, frees = 0)'</td><td>Describe pointer escape and invalidation behavior</td></tr>
</table>
<p><span class="code-inline">SafetyWhat</span> is shared by runtime safety and static sanity, although not every flag has meaningful behavior in both systems. See the dedicated safety and sanity chapters before overriding defaults.</p>
<p><span class="code-inline">BorrowSummary</span> is emitted automatically for ordinary Swag functions. Write it manually only for a foreign declaration whose ownership behavior the compiler cannot inspect.</p>
<h3 id="Native_Interoperability">Native Interoperability</h3>
<div class="code-block"><span class="SCde"><span class="SAtr">#[Swag.Foreign(
    module: "native_module",
    function: "external_symbol",
    link: "native_import_library",
    callconv: .C)]</span>
<span class="SKwd">func</span> <span class="SFct">localName</span>(value: <span class="STpe">u32</span>)-&gt;<span class="STpe">u32</span>
</span></div>
<p><span class="code-inline">function</span> defaults to the local declaration name, <span class="code-inline">link</span> defaults to the module name, and <span class="code-inline">callconv</span> defaults to the target C ABI.</p>
<h3 id="Documentation">Documentation</h3>
<table class="table-markdown">
<tr><th>Attribute</th><th>Purpose</th></tr>
<tr><td><span class="code-inline">NoDoc()</span></td><td>Exclude an otherwise public declaration from generated API documentation</td></tr>
</table>
<p>Use <span class="code-inline">Swag.NoDoc</span> only for declarations that are intentionally public but unsuitable for the generated API reference. It does not change visibility or module API export.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h2 id="_011_000_scoping_swg">Scoping</h2>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>
</span></div>
<p>Scopes determine where a name is visible and when cleanup runs. Namespaces organize module-level symbols; <span class="code-inline">using</span> and <span class="code-inline">with</span> shorten access; <span class="code-inline">defer</span> schedules work at lexical-scope exit.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_011_001_namespace_swg">Namespace</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Namespaces">Namespaces</h3>
<p>Namespaces in Swag provide a structured way to organize symbols such as functions, variables, and types within a specific scope. Grouping related symbols under a namespace helps prevent naming conflicts and makes the code more modular and maintainable.</p>
<p>Symbols in a namespace are accessible only through that namespace unless they are explicitly imported or exposed.</p>
<div class="code-block"><span class="SCde">
<span class="SCmt">// Define a simple namespace 'A'</span>
<span class="SKwd">namespace</span> <span class="SCst">A</span>
{
    <span class="SCmt">// Function 'a' is defined within the namespace 'A'.</span>
    <span class="SKwd">func</span> <span class="SFct">a</span>() =&gt; <span class="SNum">1</span>
}

</span></div>
<h3 id="Nested_Namespaces">Nested Namespaces</h3>
<p>Swag supports nested namespaces, allowing hierarchical organization of symbols. This enables fine-grained structuring of code, which is especially helpful in large projects. In the example below, <span class="code-inline">C</span> is nested inside <span class="code-inline">B</span>, which is nested inside <span class="code-inline">A</span>.</p>
<div class="code-block"><span class="SCde">
<span class="SCmt">// Define a nested namespace 'A.B.C'</span>
<span class="SKwd">namespace</span> <span class="SCst">A</span>.<span class="SCst">B</span>.<span class="SCst">C</span>
{
    <span class="SCmt">// Function 'a' is defined within the nested namespace 'A.B.C'.</span>
    <span class="SKwd">func</span> <span class="SFct">a</span>() =&gt; <span class="SNum">2</span>
}

<span class="SFct">#test</span>
{
    <span class="SCmt">// Access functions using their fully qualified namespace paths.</span>
    <span class="SItr">@assert</span>(<span class="SCst">A</span>.<span class="SFct">a</span>() == <span class="SNum">1</span>)         <span class="SCmt">// Calls 'a' from namespace 'A'</span>
    <span class="SItr">@assert</span>(<span class="SCst">A</span>.<span class="SCst">B</span>.<span class="SCst">C</span>.<span class="SFct">a</span>() == <span class="SNum">2</span>)     <span class="SCmt">// Calls 'a' from nested namespace 'A.B.C'</span>
}

</span></div>
<h3 id="Qualified_Namespace_Access">Qualified Namespace Access</h3>
<p>Symbols from a namespace are accessed through their qualified name.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">namespace</span> <span class="SCst">QualifiedExample</span>
{
    <span class="SKwd">const</span> <span class="SCst">Symbol</span> = <span class="SNum">0</span>     <span class="SCmt">// Constant defined within namespace 'QualifiedExample'</span>
}

<span class="SKwd">const</span> <span class="SCst">B</span> = <span class="SCst">QualifiedExample</span>.<span class="SCst">Symbol</span>     <span class="SCmt">// Access via fully qualified name</span>

</span></div>
<h3 id="Internal_Scopes">Internal Scopes</h3>
<p>In addition to named namespaces, Swag provides <span class="code-inline">internal</span> scopes. An internal scope creates a unique, unnamed namespace restricted to the current file. Symbols defined in such a scope are inaccessible outside it, making this useful for isolating private details.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">internal</span>
{
    <span class="SKwd">const</span> <span class="SCst">OtherSymbol</span> = <span class="SNum">0</span>     <span class="SCmt">// Constant defined in an internal scope</span>
}

<span class="SKwd">const</span> <span class="SCst">D</span> = <span class="SCst">OtherSymbol</span>     <span class="SCmt">// Accessible within this file only</span>

</span></div>
<h3 id="Exporting_Symbols">Exporting Symbols</h3>
<p>By default, all symbols in a Swag file are exported to other files within the same module. Using explicit namespaces or internal scopes provides protection against accidental symbol conflicts across files.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_011_002_defer_swg">Defer</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="The__defer__Statement">The <span class="code-inline">defer</span> Statement</h3>
<p>The <span class="code-inline">defer</span> statement registers an expression that executes automatically when the current scope is exited. The registration is resolved at compile time, so there is no runtime bookkeeping: the compiler emits the deferred code on every exit path. This keeps cleanup and finalization close to the acquisition that needs them.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> v = <span class="SNum">0</span>
    <span class="SLgc">defer</span> <span class="SItr">@assert</span>(v == <span class="SNum">1</span>)     <span class="SCmt">// Ensures v equals 1 on scope exit.</span>
    v += <span class="SNum">1</span>                    <span class="SCmt">// Increment v.</span>

<span class="SCmt">// When the scope ends, the deferred expression executes here.</span>
}

</span></div>
<h3 id="Deferring_a_Block">Deferring a Block</h3>
<p>A <span class="code-inline">defer</span> can also enclose multiple expressions within a block. This allows you to group operations that should all run when leaving the scope.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> v = <span class="SNum">0</span>
    <span class="SLgc">defer</span>
    {
        v += <span class="SNum">10</span>
        <span class="SItr">@assert</span>(v == <span class="SNum">15</span>)
    }

    v += <span class="SNum">5</span>

<span class="SCmt">// Upon scope exit, the defer block executes, ensuring v == 15.</span>
}

</span></div>
<h3 id="_defer__and_Control_Flow"><span class="code-inline">defer</span> and Control Flow</h3>
<p>The deferred expression executes every time a scope exits, even when leaving via <span class="code-inline">return</span>, <span class="code-inline">break</span>, or <span class="code-inline">continue</span>. This guarantees proper cleanup in all control flow paths.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> <span class="SCst">G</span> = <span class="SNum">0</span>
    <span class="SLgc">for</span> <span class="SNum">10</span>
    {
        <span class="SLgc">defer</span> <span class="SCst">G</span> += <span class="SNum">1</span>     <span class="SCmt">// Increment G at end of each iteration, even if broken.</span>

        <span class="SLgc">if</span> <span class="SCst">G</span> == <span class="SNum">2</span> <span class="SLgc">do</span>
            <span class="SLgc">break</span>     <span class="SCmt">// Exiting early still triggers the defer expression.</span>
    }

    <span class="SItr">@assert</span>(<span class="SCst">G</span> == <span class="SNum">3</span>)
}

</span></div>
<h3 id="Deferred_Execution_Order">Deferred Execution Order</h3>
<p>When multiple <span class="code-inline">defer</span> statements exist, they execute in reverse declaration order. The most recent defer runs first when the scope ends.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> x = <span class="SNum">1</span>
    <span class="SLgc">defer</span> <span class="SItr">@assert</span>(x == <span class="SNum">2</span>)     <span class="SCmt">// Executes second</span>
    <span class="SLgc">defer</span> x *= <span class="SNum">2</span>              <span class="SCmt">// Executes first</span>

<span class="SCmt">// Execution order is reversed for predictable cleanup flow.</span>
}

</span></div>
<h3 id="Example__Resource_Management">Example: Resource Management</h3>
<p><span class="code-inline">defer</span> is ideal for resource handling — ensuring that allocation and release logic stay close together and cleanup always happens.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">func</span> <span class="SFct">createResource</span>() =&gt; <span class="SKwd">true</span>

    <span class="SKwd">func</span> <span class="SFct">releaseResource</span>(resource: *<span class="STpe">bool</span>)
    {
        <span class="SKwd">dref</span> resource = <span class="SKwd">false</span>
    }

    <span class="SKwd">func</span> <span class="SFct">isResourceCreated</span>(b: <span class="STpe">bool</span>) =&gt; b

    <span class="SKwd">var</span> resource = <span class="SKwd">false</span>
    <span class="SLgc">for</span> <span class="SNum">10</span>
    {
        resource = <span class="SFct">createResource</span>()
        <span class="SLgc">defer</span>
        {
            <span class="SItr">@assert</span>(resource.<span class="SFct">isResourceCreated</span>())
            <span class="SFct">releaseResource</span>(&amp;resource)
        }

        <span class="SLgc">if</span> <span class="SItr">@index</span> == <span class="SNum">2</span> <span class="SLgc">do</span>
            <span class="SLgc">break</span>     <span class="SCmt">// Defer ensures cleanup even on early exit.</span>
    }

    <span class="SItr">@assert</span>(!resource.<span class="SFct">isResourceCreated</span>())
}

</span></div>
<h3 id="Example__Error_Handling">Example: Error Handling</h3>
<p><span class="code-inline">defer</span> ensures reliable cleanup even in functions that may return early due to errors. This pattern creates robust, error-resilient code.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">func</span> <span class="SFct">createResource</span>() =&gt; <span class="SKwd">true</span>

    <span class="SKwd">func</span> <span class="SFct">releaseResource</span>(resource: *<span class="STpe">bool</span>)
    {
        <span class="SKwd">dref</span> resource = <span class="SKwd">false</span>
    }

    <span class="SKwd">func</span> <span class="SFct">isResourceCreated</span>(b: <span class="STpe">bool</span>) =&gt; b

    <span class="SKwd">func</span> <span class="SFct">performTask</span>()-&gt;<span class="STpe">bool</span>
    {
        <span class="SKwd">var</span> resource = <span class="SFct">createResource</span>()
        <span class="SLgc">defer</span> <span class="SFct">releaseResource</span>(&amp;resource)     <span class="SCmt">// Always release resource.</span>

        <span class="SLgc">if</span> !resource.<span class="SFct">isResourceCreated</span>()
        {
            <span class="SCmt">// Early return still triggers defer.</span>
            <span class="SLgc">return</span> <span class="SKwd">false</span>
        }

        <span class="SCmt">// Perform work...</span>
        <span class="SLgc">return</span> <span class="SKwd">true</span>
    }

    <span class="SKwd">let</span> success = <span class="SFct">performTask</span>()
    <span class="SItr">@assert</span>(success)
}

</span></div>
<h3 id="_011_003_using_swg">Using</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="_using__with_Enums_and_Namespaces"><span class="code-inline">using</span> with Enums and Namespaces</h3>
<p>The <span class="code-inline">using</span> statement can bring the scope of a namespace, struct, or enum into the current context. This removes the need for full qualification when accessing members. For enums, it simplifies code by avoiding repetitive type prefixes.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">enum</span> <span class="SCst">RGB</span> { <span class="SCst">R</span>, <span class="SCst">G</span>, <span class="SCst">B</span> }
    <span class="SItr">@assert</span>(<span class="SCst">RGB</span>.<span class="SCst">R</span> == <span class="SNum">0</span>)     <span class="SCmt">// Fully qualified access.</span>

    <span class="SKwd">using</span> <span class="SCst">RGB</span>           <span class="SCmt">// Import enum members into the current scope.</span>
    <span class="SItr">@assert</span>(<span class="SCst">G</span> == <span class="SNum">1</span>)     <span class="SCmt">// 'G' accessible directly without 'RGB.' prefix.</span>
}

</span></div>
<h3 id="_using__with_Struct_Fields"><span class="code-inline">using</span> with Struct Fields</h3>
<p>The <span class="code-inline">using</span> statement can be applied to struct fields, exposing the fields of a nested struct as if they were part of the containing struct. This is useful for composition-like behavior, improving code readability and reducing nesting.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">struct</span> <span class="SCst">Point2</span>
    {
        x, y: <span class="STpe">s32</span>
    }

    <span class="SKwd">struct</span> <span class="SCst">Point3</span>
    {
        <span class="SKwd">using</span> base: <span class="SCst">Point2</span>     <span class="SCmt">// Bring 'Point2' fields into 'Point3' scope.</span>
        z:          <span class="STpe">s32</span>
    }

    <span class="SKwd">var</span> value: <span class="SCst">Point3</span>

    <span class="SCmt">// Fields from 'base' are directly accessible.</span>
    value.x = <span class="SNum">0</span>
    value.y = <span class="SNum">0</span>
    value.z = <span class="SNum">0</span>

    <span class="SItr">@assert</span>(&amp;value.x == &amp;value.base.x)
    <span class="SItr">@assert</span>(&amp;value.y == &amp;value.base.y)

    <span class="SCmt">// Automatic cast: Point3 can be treated as Point2.</span>
    <span class="SKwd">func</span> <span class="SFct">set1</span>(ptr: *<span class="SCst">Point2</span>)
    {
        ptr.x, ptr.y = <span class="SNum">1</span>
    }

    <span class="SFct">set1</span>(&amp;value)

    <span class="SItr">@assert</span>(value.x == <span class="SNum">1</span>)
    <span class="SItr">@assert</span>(value.y == <span class="SNum">1</span>)
    <span class="SItr">@assert</span>(value.base.x == <span class="SNum">1</span>)
    <span class="SItr">@assert</span>(value.base.y == <span class="SNum">1</span>)
}

</span></div>
<h3 id="_011_004_with_swg">With</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="The__with__Statement">The <span class="code-inline">with</span> Statement</h3>
<p>The <span class="code-inline">with</span> statement reduces repetition by letting you access fields and methods of a variable, struct, or namespace within a scoped block. Inside a <span class="code-inline">with</span> block, the <span class="code-inline">.</span> prefix refers to the selected object, yielding concise, readable code.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">struct</span> <span class="SCst">Point</span>
{
    x, y: <span class="STpe">s32</span>
}

<span class="SKwd">impl</span> <span class="SCst">Point</span>
{
    <span class="SKwd">mtd</span> <span class="SFct">setOne</span>()
    {
        <span class="STpe">me</span>.x, <span class="STpe">me</span>.y = <span class="SNum">1</span>

    <span class="SCmt">// Set both coordinates to 1 on this Point.</span>
    }
}

</span></div>
<h3 id="_with__and_a_Namespace"><span class="code-inline">with</span> and a Namespace</h3>
<p>You can apply <span class="code-inline">with</span> to a namespace to call functions or access constants without fully qualifying names.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">namespace</span> <span class="SCst">NameSpace</span>
{
    <span class="SKwd">func</span> <span class="SFct">inside0</span>()
    {
    <span class="SCmt">// Example namespaced function.</span>
    }

    <span class="SKwd">func</span> <span class="SFct">inside1</span>()
    {
    <span class="SCmt">// Another namespaced function.</span>
    }
}

</span></div>
<h3 id="_with__on_a_Variable"><span class="code-inline">with</span> on a Variable</h3>
<p>Use <span class="code-inline">with</span> with a variable to streamline field access without repeating the variable name.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> pt: <span class="SCst">Point</span>
    <span class="SKwd">with</span> pt
    {
        .x = <span class="SNum">1</span>     <span class="SCmt">// Equivalent to 'pt.x = 1'</span>
        .y = <span class="SNum">2</span>     <span class="SCmt">// Equivalent to 'pt.y = 2'</span>
    }

    <span class="SItr">@assert</span>(pt.x == <span class="SNum">1</span>)
    <span class="SItr">@assert</span>(pt.y == <span class="SNum">2</span>)
}

</span></div>
<h3 id="Calling_Functions_inside__with_">Calling Functions inside <span class="code-inline">with</span></h3>
<p>Inside a <span class="code-inline">with</span> block, you can invoke methods and access fields directly.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> pt: <span class="SCst">Point</span>
    <span class="SKwd">with</span> pt
    {
        .<span class="SFct">setOne</span>()     <span class="SCmt">// Equivalent to 'pt.setOne()'</span>
        .y = <span class="SNum">2</span>        <span class="SCmt">// Adjust a single field afterward</span>
        <span class="SItr">@assert</span>(.x == <span class="SNum">1</span>)
        <span class="SItr">@assert</span>(.y == <span class="SNum">2</span>)
    }

    <span class="SItr">@assert</span>(pt.x == <span class="SNum">1</span>)
    <span class="SItr">@assert</span>(pt.y == <span class="SNum">2</span>)
}

</span></div>
<h3 id="Using_Names_from_a__with__Namespace">Using Names from a <span class="code-inline">with</span> Namespace</h3>
<p>Demonstrates calling namespaced functions via <span class="code-inline">with</span>.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">with</span> <span class="SCst">NameSpace</span>
    {
        .<span class="SFct">inside0</span>()
        .<span class="SFct">inside1</span>()
    }
}

</span></div>
<h3 id="Declaring_a_Variable_with__with_">Declaring a Variable with <span class="code-inline">with</span></h3>
<p>You can declare a variable directly in the <span class="code-inline">with</span> header and work with it immediately inside the block.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">with</span> <span class="SKwd">var</span> pt = <span class="SCst">Point</span>{<span class="SNum">1</span>, <span class="SNum">2</span>}
    {
        .x = <span class="SNum">10</span>
        .y = <span class="SNum">20</span>
    }

    <span class="SItr">@assert</span>(pt.x == <span class="SNum">10</span> <span class="SLgc">and</span> pt.y == <span class="SNum">20</span>)
}

<span class="SFct">#test</span>
{
    <span class="SKwd">with</span> <span class="SKwd">var</span> pt: <span class="SCst">Point</span>     <span class="SCmt">// Declaration without initializer</span>
    {
        .x = <span class="SNum">10</span>
        .y = <span class="SNum">20</span>
    }

    <span class="SItr">@assert</span>(pt.x == <span class="SNum">10</span> <span class="SLgc">and</span> pt.y == <span class="SNum">20</span>)
}

</span></div>
<h3 id="Assignment_inside__with_">Assignment inside <span class="code-inline">with</span></h3>
<p>You can also use <span class="code-inline">with</span> on an assignment to modify the freshly assigned value immediately.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> pt: <span class="SCst">Point</span>
    <span class="SKwd">with</span> pt = <span class="SCst">Point</span>{<span class="SNum">1</span>, <span class="SNum">2</span>}
    {
        .x = <span class="SNum">10</span>
        .y = <span class="SNum">20</span>
    }

    <span class="SItr">@assert</span>(pt.x == <span class="SNum">10</span> <span class="SLgc">and</span> pt.y == <span class="SNum">20</span>)
}

</span></div>
<h2 id="_012_000_type_reflection_swg">Type Reflection</h2>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Types_as_Values">Types as Values</h3>
<p>In Swag, types are treated as first-class values that can be inspected and manipulated at both compile time and runtime. This enables powerful metaprogramming patterns for flexible, reusable code.</p>
<p>The primary intrinsics for interacting with types are <span class="code-inline">#typeof</span> and <span class="code-inline">@kindof</span>, which let you introspect and work with types dynamically.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="Using___typeof__to_Inspect_Types">Using <span class="code-inline">#typeof</span> to Inspect Types</h3>
<p>The <span class="code-inline">#typeof</span> intrinsic retrieves the type information of an expression. When an expression explicitly represents a type, you can also use the type itself. This is useful for compile-time inspection and validation.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SCmt">// Basic types via '#typeof' and direct type usage</span>
    <span class="SKwd">let</span> ptr1 = <span class="SItr">#typeof</span>(<span class="STpe">s8</span>)
    <span class="SItr">@assert</span>(ptr1.name == <span class="SStr">"s8"</span>)
    <span class="SItr">@assert</span>(ptr1 == <span class="STpe">s8</span>)

    <span class="SKwd">let</span> ptr2 = <span class="SItr">#typeof</span>(<span class="STpe">s16</span>)
    <span class="SItr">@assert</span>(ptr2.name == <span class="SStr">"s16"</span>)
    <span class="SItr">@assert</span>(ptr2 == <span class="STpe">s16</span>)

    <span class="SKwd">let</span> ptr3 = <span class="STpe">s32</span>
    <span class="SItr">@assert</span>(ptr3.name == <span class="SStr">"s32"</span>)
    <span class="SItr">@assert</span>(ptr3 == <span class="SItr">#typeof</span>(<span class="STpe">s32</span>))

    <span class="SKwd">let</span> ptr4 = <span class="STpe">s64</span>
    <span class="SItr">@assert</span>(ptr4.name == <span class="SStr">"s64"</span>)
    <span class="SItr">@assert</span>(ptr4 == <span class="STpe">s64</span>)
}

</span></div>
<h3 id="Understanding_the_Result_of___typeof_">Understanding the Result of <span class="code-inline">#typeof</span></h3>
<p><span class="code-inline">#typeof</span> yields a constant pointer to a <span class="code-inline">Swag.TypeInfo</span> structure (alias of <span class="code-inline">typeinfo</span>). Each Swag type maps to a specific <span class="code-inline">TypeInfo</span> descriptor in the <span class="code-inline">Swag</span> namespace, which is part of the compiler runtime.</p>
<div class="blockquote blockquote-note">
<div class="blockquote-title-block"><span class="blockquote-title">Note</span></div>
<p>The complete descriptor layouts are part of the compiler runtime API in <span class="code-inline">bin/runtime/api.swg</span>.</p>
</div>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SCmt">// Native type -&gt; native typeinfo</span>
    <span class="SKwd">let</span> ptr = <span class="STpe">bool</span>
    <span class="SItr">@assert</span>(<span class="SItr">#nameof</span>(<span class="SItr">#typeof</span>(ptr)) == <span class="SStr">"const *TypeInfoNative"</span>)

    <span class="SCmt">// Use '#type' to disambiguate when the expression could be parsed as a value</span>
    <span class="SKwd">let</span> ptr1 = <span class="SItr">#type</span> [<span class="SNum">2</span>] <span class="STpe">s32</span>
    <span class="SItr">@assert</span>(<span class="SItr">#nameof</span>(<span class="SItr">#typeof</span>(ptr1)) == <span class="SStr">"const *TypeInfoArray"</span>)
    <span class="SItr">@assert</span>(ptr1.name == <span class="SStr">"[2] s32"</span>)

    <span class="SCmt">// Array literal -&gt; array typeinfo</span>
    <span class="SKwd">let</span> ptr2 = <span class="SItr">#typeof</span>([<span class="SNum">1</span>, <span class="SNum">2</span>, <span class="SNum">3</span>])
    <span class="SItr">@assert</span>(<span class="SItr">#nameof</span>(<span class="SItr">#typeof</span>(ptr2)) == <span class="SStr">"const *TypeInfoArray"</span>)
    <span class="SItr">@assert</span>(ptr2.name == <span class="SStr">"const [3] s32"</span>)
}

</span></div>
<h3 id="Working_with__TypeInfo__Structures">Working with <span class="code-inline">TypeInfo</span> Structures</h3>
<p><span class="code-inline">TypeInfo</span> exposes a <span class="code-inline">kind</span> field identifying the category: native, pointer, array, struct, etc. This is essential when handling types generically.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SCmt">// 'f64' is a native type</span>
    <span class="SKwd">let</span> typeOf = <span class="STpe">f64</span>
    <span class="SItr">@assert</span>(typeOf.kind == <span class="SCst">Swag</span>.<span class="SCst">TypeInfoKind</span>.<span class="SCst">Native</span>)

    <span class="SCmt">// Compile-time checks of kind</span>
    <span class="SKwd">using</span> <span class="SCst">Swag</span>
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(<span class="SItr">#null</span> *<span class="STpe">u8</span>).kind == <span class="SCst">TypeInfoKind</span>.<span class="SCst">Pointer</span>)     <span class="SCmt">// Pointer</span>
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>([<span class="SNum">1</span>, <span class="SNum">2</span>, <span class="SNum">3</span>]).kind == <span class="SCst">TypeInfoKind</span>.<span class="SCst">Array</span>)       <span class="SCmt">// Array</span>
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>({<span class="SNum">1</span>, <span class="SNum">2</span>, <span class="SNum">3</span>}).kind == <span class="SCst">TypeInfoKind</span>.<span class="SCst">Struct</span>)      <span class="SCmt">// Struct</span>
}

</span></div>
<h3 id="The___decltype__Query">The <span class="code-inline">#decltype</span> Query</h3>
<p><span class="code-inline">#decltype</span> performs the reverse of <span class="code-inline">#typeof</span>/<span class="code-inline">@kindof</span>: it converts a <span class="code-inline">typeinfo</span> back into a compiler type. Use it to materialize a type determined by compile-time information.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SCmt">// Create a variable whose type is resolved from typeinfo</span>
    <span class="SKwd">var</span> x: <span class="SItr">#decltype</span>(<span class="SItr">#typeof</span>(<span class="STpe">s32</span>))
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(x) == <span class="STpe">s32</span>)
}

</span></div>
<h3 id="Using___decltype__with_Compile-Time_Expressions">Using <span class="code-inline">#decltype</span> with Compile-Time Expressions</h3>
<p><span class="code-inline">#decltype</span> can evaluate a constexpr that returns a <span class="code-inline">typeinfo</span> and materialize the corresponding type. This enables dynamic yet type-safe patterns.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SCmt">// Return a typeinfo based on a constexpr condition</span>
    <span class="SAtr">#[Swag.ConstExpr]</span>
    <span class="SKwd">func</span> <span class="SFct">getType</span>(needAString: <span class="STpe">bool</span>)-&gt;<span class="STpe">typeinfo</span>
    {
        <span class="SLgc">if</span> needAString <span class="SLgc">do</span>
            <span class="SLgc">return</span> <span class="SItr">#null</span> <span class="STpe">string</span>
        <span class="SLgc">else</span> <span class="SLgc">do</span>
            <span class="SLgc">return</span> <span class="STpe">s32</span>
    }

    <span class="SCmt">// Materialize the chosen type via '#decltype'</span>
    <span class="SKwd">var</span> x: <span class="SItr">#decltype</span>(<span class="SFct">getType</span>(needAString: <span class="SKwd">false</span>))
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(x) == <span class="STpe">s32</span>)
    x = <span class="SNum">0</span>

    <span class="SKwd">var</span> x1: <span class="SItr">#decltype</span>(<span class="SFct">getType</span>(needAString: <span class="SKwd">true</span>))
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(x1) == <span class="SItr">#null</span> <span class="STpe">string</span>)
    x1 = <span class="SStr">"0"</span>
}

</span></div>
<h3 id="_012_001_aggregate_reflection_swg">Aggregate Reflection</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Struct_and_Enum_Reflection">Struct and Enum Reflection</h3>
<p>Every <span class="code-inline">typeinfo</span> begins with <span class="code-inline">Swag.TypeInfo</span>. Inspect its <span class="code-inline">kind</span> before casting to a specialized descriptor. A struct descriptor exposes layout, fields, interfaces, lifecycle hooks, generic arguments, and any methods requested with <span class="code-inline">Swag.ExportType</span>.</p>
<div class="code-block"><span class="SCde">
<span class="SAtr">#[Swag.ExportType(.Methods)]</span>
<span class="SKwd">struct</span> <span class="SCst">ReflectedPoint</span>
{
    x: <span class="STpe">s32</span>
    y: <span class="STpe">s32</span>
}

<span class="SKwd">impl</span> <span class="SCst">ReflectedPoint</span>
{
    <span class="SKwd">mtd</span> <span class="SFct">sum</span>()-&gt;<span class="STpe">s32</span> =&gt; .x + .y
}

<span class="SKwd">enum</span> <span class="SCst">ReflectedState</span>: <span class="STpe">u8</span>
{
    <span class="SCst">Idle</span>
    <span class="SCst">Running</span>
    <span class="SCst">Done</span>
}

<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> base = <span class="SItr">#typeof</span>(<span class="SCst">ReflectedPoint</span>)
    <span class="SItr">@assert</span>(base.kind == .<span class="SCst">Struct</span>)

    <span class="SKwd">let</span> type   = <span class="SKwd">cast</span>(<span class="SKwd">const</span> *<span class="SCst">Swag</span>.<span class="SCst">TypeInfoStruct</span>) base
    <span class="SKwd">let</span> fields = <span class="SKwd">notnull</span> type.fields

    <span class="SItr">@assert</span>(type.structName == <span class="SStr">"ReflectedPoint"</span>)
    <span class="SItr">@assert</span>(type.sizeof == <span class="SItr">#sizeof</span>(<span class="SCst">ReflectedPoint</span>))
    <span class="SItr">@assert</span>(<span class="SItr">@countof</span>(fields) == <span class="SNum">2</span>)
    <span class="SItr">@assert</span>(fields[<span class="SNum">0</span>].name == <span class="SStr">"x"</span>)
    <span class="SItr">@assert</span>(fields[<span class="SNum">0</span>].pointedType == <span class="STpe">s32</span>)
    <span class="SItr">@assert</span>(fields[<span class="SNum">0</span>].offset == <span class="SItr">#offsetof</span>(<span class="SCst">ReflectedPoint</span>.x))
    <span class="SItr">@assert</span>(fields[<span class="SNum">1</span>].name == <span class="SStr">"y"</span>)
    <span class="SItr">@assert</span>(fields[<span class="SNum">1</span>].offset == <span class="SItr">#offsetof</span>(<span class="SCst">ReflectedPoint</span>.y))

    <span class="SKwd">let</span> methods = <span class="SKwd">notnull</span> type.methods
    <span class="SItr">@assert</span>(<span class="SItr">@countof</span>(methods) == <span class="SNum">1</span>)
    <span class="SItr">@assert</span>(methods[<span class="SNum">0</span>].name == <span class="SStr">"sum"</span>)
    <span class="SItr">@assert</span>((<span class="SKwd">notnull</span> methods[<span class="SNum">0</span>].pointedType).kind == .<span class="SCst">Func</span>)
}

</span></div>
<p>An enum descriptor reports the storage type and one <span class="code-inline">TypeValue</span> per named value. <span class="code-inline">TypeValue.value</span> is an untyped pointer to the exported constant; use a typed reflection helper before reading it in general-purpose code.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> base = <span class="SItr">#typeof</span>(<span class="SCst">ReflectedState</span>)
    <span class="SItr">@assert</span>(base.kind == .<span class="SCst">Enum</span>)

    <span class="SKwd">let</span> type   = <span class="SKwd">cast</span>(<span class="SKwd">const</span> *<span class="SCst">Swag</span>.<span class="SCst">TypeInfoEnum</span>) base
    <span class="SKwd">let</span> values = <span class="SKwd">notnull</span> type.values

    <span class="SItr">@assert</span>(type.rawType == <span class="STpe">u8</span>)
    <span class="SItr">@assert</span>(<span class="SItr">@countof</span>(values) == <span class="SNum">3</span>)
    <span class="SItr">@assert</span>(values[<span class="SNum">0</span>].name == <span class="SStr">"Idle"</span>)
    <span class="SItr">@assert</span>(values[<span class="SNum">1</span>].name == <span class="SStr">"Running"</span>)
    <span class="SItr">@assert</span>(values[<span class="SNum">2</span>].name == <span class="SStr">"Done"</span>)
    <span class="SItr">@assert</span>(values[<span class="SNum">0</span>].pointedType == <span class="SCst">ReflectedState</span>)
}

</span></div>
<p>Reflection describes declarations; it does not bypass visibility, constness, or ownership. When writing a generic serializer or editor, validate <span class="code-inline">kind</span>, check nullable descriptor slices, and derive field addresses from a live instance plus <span class="code-inline">TypeValue.offset</span>.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_012_002_function_and_container_reflection_swg">Function and Container Reflection</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Function_Reflection">Function Reflection</h3>
<p><span class="code-inline">#typeof</span> on a function yields <span class="code-inline">Swag.TypeInfoFunc</span>. Its parameter entries are <span class="code-inline">TypeValue</span> records, and <span class="code-inline">returnType</span> is <span class="code-inline">null</span> for a function with no return value.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">func</span> <span class="SFct">reflectedAdd</span>(left: <span class="STpe">s32</span>, right: <span class="STpe">s32</span>)-&gt;<span class="STpe">s32</span>
{
    <span class="SLgc">return</span> left + right
}

<span class="SKwd">func</span> <span class="SFct">reflectedNotify</span>(value: <span class="STpe">bool</span>)
{
    <span class="SKwd">discard</span> value
}

<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> type       = <span class="SKwd">cast</span>(<span class="SKwd">const</span> *<span class="SCst">Swag</span>.<span class="SCst">TypeInfoFunc</span>) <span class="SItr">#typeof</span>(reflectedAdd)
    <span class="SKwd">let</span> parameters = <span class="SKwd">notnull</span> type.parameters

    <span class="SItr">@assert</span>(<span class="SItr">@countof</span>(parameters) == <span class="SNum">2</span>)
    <span class="SItr">@assert</span>(parameters[<span class="SNum">0</span>].name == <span class="SStr">"left"</span>)
    <span class="SItr">@assert</span>(parameters[<span class="SNum">0</span>].pointedType == <span class="STpe">s32</span>)
    <span class="SItr">@assert</span>(parameters[<span class="SNum">1</span>].name == <span class="SStr">"right"</span>)
    <span class="SItr">@assert</span>(parameters[<span class="SNum">1</span>].pointedType == <span class="STpe">s32</span>)
    <span class="SItr">@assert</span>(type.returnType == <span class="STpe">s32</span>)

    <span class="SKwd">let</span> noResult = <span class="SKwd">cast</span>(<span class="SKwd">const</span> *<span class="SCst">Swag</span>.<span class="SCst">TypeInfoFunc</span>) <span class="SItr">#typeof</span>(reflectedNotify)
    <span class="SItr">@assert</span>(noResult.returnType == <span class="SKwd">null</span>)
}

</span></div>
<h3 id="Pointer__Array__and_Slice_Reflection">Pointer, Array, and Slice Reflection</h3>
<p>Container descriptors identify their element type. Arrays additionally expose their dimensions; pointer and slice descriptors expose the pointed-to type.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> pointer = <span class="SKwd">cast</span>(<span class="SKwd">const</span> *<span class="SCst">Swag</span>.<span class="SCst">TypeInfoPointer</span>) <span class="SItr">#type</span> *<span class="STpe">s32</span>
    <span class="SItr">@assert</span>(pointer.kind == .<span class="SCst">Pointer</span>)
    <span class="SItr">@assert</span>(pointer.pointedType == <span class="STpe">s32</span>)

    <span class="SKwd">let</span> array = <span class="SKwd">cast</span>(<span class="SKwd">const</span> *<span class="SCst">Swag</span>.<span class="SCst">TypeInfoArray</span>) <span class="SItr">#type</span> [<span class="SNum">2</span>, <span class="SNum">3</span>] <span class="STpe">u16</span>
    <span class="SItr">@assert</span>(array.kind == .<span class="SCst">Array</span>)
    <span class="SItr">@assert</span>(array.pointedType == <span class="SItr">#type</span> [<span class="SNum">3</span>] <span class="STpe">u16</span>)
    <span class="SItr">@assert</span>(array.finalType == <span class="STpe">u16</span>)
    <span class="SItr">@assert</span>(array.count == <span class="SNum">2</span>)
    <span class="SItr">@assert</span>(array.totalCount == <span class="SNum">6</span>)

    <span class="SKwd">let</span> slice = <span class="SKwd">cast</span>(<span class="SKwd">const</span> *<span class="SCst">Swag</span>.<span class="SCst">TypeInfoSlice</span>) <span class="SItr">#type</span> [..] <span class="STpe">f32</span>
    <span class="SItr">@assert</span>(slice.kind == .<span class="SCst">Slice</span>)
    <span class="SItr">@assert</span>(slice.pointedType == <span class="STpe">f32</span>)
}

</span></div>
<h2 id="_013_000_error_management_and_safety_swg">Error Management and Safety</h2>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>
</span></div>
<p>Swag separates three concerns:</p>
<ul>
<li>fallible functions propagate error values with <span class="code-inline">fail</span>, <span class="code-inline">try</span>, and <span class="code-inline">catch</span>;</li>
<li>runtime safety guards detect invalid operations in generated code;</li>
<li>static sanity checks reject faults the compiler can prove.</li>
</ul>
<p>Build configuration selects defaults, and attributes can narrow them for a declaration or scope.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_013_001_error_management_swg">Error Management</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Error_Management">Error Management</h3>
<p>Swag models errors as values. A function marked with <span class="code-inline">fail</span> can either return its normal result or exit early with 'fail errorValue'. The caller then chooses whether to propagate, catch, dismiss, or expect success.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">struct</span> <span class="SCst">MyError</span>
{
    <span class="SKwd">using</span> base: <span class="SCst">Swag</span>.<span class="SCst">BaseError</span>
    code:       <span class="STpe">s32</span> = <span class="SNum">0</span>
}

<span class="SKwd">func</span> <span class="SFct">count</span>(name: <span class="SItr">#null</span> <span class="STpe">string</span>)-&gt;<span class="STpe">u64</span> <span class="SKwd">fail</span>
{
    <span class="SLgc">if</span> name == <span class="SKwd">null</span> <span class="SLgc">do</span>
        <span class="SKwd">fail</span> <span class="SCst">MyError</span>{base: <span class="SCst">Swag</span>.<span class="SCst">BaseError</span>{<span class="SStr">"name cannot be null"</span>}, code: <span class="SNum">7</span>}
    <span class="SLgc">return</span> <span class="SItr">@countof</span>(name)
}

</span></div>
<h3 id="Catching_Errors">Catching Errors</h3>
<p><span class="code-inline">catch</span> handles the error locally and returns the default value for the result type. To inspect the error, capture it with 'as err': this binds a fresh local (of type '#null any') that is null on success and holds the caught error on failure. The capture is visible in the enclosing scope, after the catch, so each capture in a given scope needs its own name.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> value = <span class="SKwd">catch</span> <span class="SFct">count</span>(<span class="SKwd">null</span>) <span class="SLgc">as</span> err
    <span class="SItr">@assert</span>(value == <span class="SNum">0</span>)
    <span class="SItr">@assert</span>(err != <span class="SKwd">null</span>)

    <span class="SKwd">let</span> e = <span class="SKwd">cast</span>(<span class="SCst">MyError</span>) err
    <span class="SItr">@assert</span>(e.code == <span class="SNum">7</span>)
    <span class="SItr">@assert</span>(e.message == <span class="SStr">"name cannot be null"</span>)
}

</span></div>
<h3 id="Handling_on_Failure_with__catch_____else_">Handling on Failure with 'catch ... else'</h3>
<p>'catch e else { H }' runs the anonymous handler <span class="code-inline">H</span> only when <span class="code-inline">e</span> fails. <span class="code-inline">H</span> cannot inspect the error (capture it with 'as err' for that); it is evaluated lazily — only on the failure path — and may divert control flow (e.g. an early <span class="code-inline">return</span>). To read the caught error, use the 'as err' capture form instead.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">recordTrace</span>(name: <span class="SItr">#null</span> <span class="STpe">string</span>, out: *<span class="STpe">s32</span>) <span class="SKwd">fail</span>
{
    <span class="SKwd">dref</span> out = <span class="SKwd">cast</span>(<span class="STpe">s32</span>) <span class="SFct">count</span>(name)
}

<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> seen: <span class="STpe">s32</span> = -<span class="SNum">1</span>

    <span class="SKwd">catch</span> <span class="SFct">recordTrace</span>(<span class="SStr">"swag"</span>, &amp;seen) <span class="SLgc">else</span> <span class="SLgc">do</span>
        seen = -<span class="SNum">2</span>
    <span class="SItr">@assert</span>(seen == <span class="SNum">4</span>)     <span class="SCmt">// success: the handler does not run</span>

    <span class="SKwd">catch</span> <span class="SFct">recordTrace</span>(<span class="SKwd">null</span>, &amp;seen) <span class="SLgc">else</span>
    {
        seen = -<span class="SNum">2</span>
    }

    <span class="SItr">@assert</span>(seen == -<span class="SNum">2</span>)     <span class="SCmt">// failure: the handler ran instead</span>
}

</span></div>
<h3 id="Dismissing_Errors">Dismissing Errors</h3>
<p>To dismiss a failure and continue with the type default, use <span class="code-inline">catch</span> without a capture: the error is handled and dropped, and the expression yields the default value for the result type. To keep the error, add an 'as err' capture; to use a custom fallback, capture and branch ('var x = catch f() as err; if err != null do x = V').</p>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">safeCount</span>(name: <span class="SItr">#null</span> <span class="STpe">string</span>)-&gt;<span class="STpe">u64</span>
{
    <span class="SLgc">return</span> <span class="SKwd">catch</span> <span class="SFct">count</span>(name)
}

<span class="SFct">#test</span>
{
    <span class="SItr">@assert</span>(<span class="SFct">safeCount</span>(<span class="SStr">"hello"</span>) == <span class="SNum">5</span>)
    <span class="SItr">@assert</span>(<span class="SFct">safeCount</span>(<span class="SKwd">null</span>) == <span class="SNum">0</span>)
}

</span></div>
<h3 id="Propagating_Errors">Propagating Errors</h3>
<p><span class="code-inline">try</span> propagates the current error to the caller, so it belongs inside a function that can itself return an error.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">propagateCount</span>(name: <span class="SItr">#null</span> <span class="STpe">string</span>)-&gt;<span class="STpe">u64</span> <span class="SKwd">fail</span>
{
    <span class="SLgc">return</span> <span class="SKwd">try</span> <span class="SFct">count</span>(name)
}

<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> value = <span class="SKwd">catch</span> <span class="SFct">propagateCount</span>(<span class="SStr">"abc"</span>) <span class="SLgc">as</span> err
    <span class="SItr">@assert</span>(value == <span class="SNum">3</span>)
    <span class="SItr">@assert</span>(err == <span class="SKwd">null</span>)
}

<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> value = <span class="SKwd">catch</span> <span class="SFct">propagateCount</span>(<span class="SKwd">null</span>) <span class="SLgc">as</span> err
    <span class="SItr">@assert</span>(value == <span class="SNum">0</span>)
    <span class="SItr">@assert</span>(err != <span class="SKwd">null</span>)
    <span class="SItr">@assert</span>((<span class="SKwd">cast</span>(<span class="SCst">MyError</span>) err).code == <span class="SNum">7</span>)
}

</span></div>
<h3 id="Implicit_try">Implicit try</h3>
<p>Inside a function declared with <span class="code-inline">fail</span>, calling another fallible function is an implicit propagation.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">implicitTryCount</span>(name: <span class="SItr">#null</span> <span class="STpe">string</span>)-&gt;<span class="STpe">u64</span> <span class="SKwd">fail</span>
{
    <span class="SLgc">return</span> <span class="SFct">count</span>(name)
}

<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> value = <span class="SKwd">catch</span> <span class="SFct">implicitTryCount</span>(<span class="SKwd">null</span>) <span class="SLgc">as</span> err
    <span class="SItr">@assert</span>(value == <span class="SNum">0</span>)
    <span class="SItr">@assert</span>(err != <span class="SKwd">null</span>)
    <span class="SItr">@assert</span>((<span class="SKwd">cast</span>(<span class="SCst">MyError</span>) err).code == <span class="SNum">7</span>)
}

</span></div>
<h3 id="Error-Handling_Blocks">Error-Handling Blocks</h3>
<p><span class="code-inline">try</span>, <span class="code-inline">catch</span> (optionally with 'as err' or <span class="code-inline">else</span>), and <span class="code-inline">expect</span> can also guard a whole block of code.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">blockTry</span>(name0: <span class="SItr">#null</span> <span class="STpe">string</span>, name1: <span class="SItr">#null</span> <span class="STpe">string</span>)-&gt;<span class="STpe">u64</span> <span class="SKwd">fail</span>
{
    <span class="SKwd">var</span> total: <span class="STpe">u64</span> = <span class="SNum">0</span>
    <span class="SKwd">try</span>
    {
        total += <span class="SFct">count</span>(name0)
        total += <span class="SFct">count</span>(name1)
    }

    <span class="SLgc">return</span> total
}

<span class="SKwd">func</span> <span class="SFct">blockCatchCode</span>()-&gt;<span class="STpe">s32</span>
{
    <span class="SKwd">catch</span>
    {
        <span class="SKwd">discard</span> <span class="SFct">count</span>(<span class="SStr">"ok"</span>)
        <span class="SKwd">discard</span> <span class="SFct">count</span>(<span class="SKwd">null</span>)
    } <span class="SLgc">as</span> err

    <span class="SLgc">if</span> err == <span class="SKwd">null</span> <span class="SLgc">do</span>
        <span class="SLgc">return</span> -<span class="SNum">1</span>

    <span class="SLgc">return</span> (<span class="SKwd">cast</span>(<span class="SCst">MyError</span>) err).code
}

<span class="SKwd">func</span> <span class="SFct">blockCatchElse</span>(name: <span class="SItr">#null</span> <span class="STpe">string</span>)-&gt;<span class="STpe">u64</span>
{
    <span class="SKwd">catch</span>
    {
        <span class="SLgc">return</span> <span class="SFct">count</span>(name)
    } <span class="SLgc">else</span> {}

    <span class="SLgc">return</span> <span class="SNum">99</span>
}

<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> value = <span class="SKwd">catch</span> <span class="SFct">blockTry</span>(<span class="SStr">"ab"</span>, <span class="SKwd">null</span>) <span class="SLgc">as</span> err
    <span class="SItr">@assert</span>(value == <span class="SNum">0</span>)
    <span class="SItr">@assert</span>(err != <span class="SKwd">null</span>)
    <span class="SItr">@assert</span>((<span class="SKwd">cast</span>(<span class="SCst">MyError</span>) err).code == <span class="SNum">7</span>)
}

<span class="SFct">#test</span>
{
    <span class="SItr">@assert</span>(<span class="SFct">blockCatchCode</span>() == <span class="SNum">7</span>)
    <span class="SItr">@assert</span>(<span class="SFct">blockCatchElse</span>(<span class="SStr">"abcd"</span>) == <span class="SNum">4</span>)
    <span class="SItr">@assert</span>(<span class="SFct">blockCatchElse</span>(<span class="SKwd">null</span>) == <span class="SNum">99</span>)
}

</span></div>
<h3 id="Expect">Expect</h3>
<p>Inside <span class="code-inline">#test</span>, <span class="code-inline">try</span> is equivalent to <span class="code-inline">expect</span>, so both forms keep the success path concise when failure is not expected.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> value = <span class="SKwd">try</span> <span class="SFct">count</span>(<span class="SStr">"swag"</span>)
    <span class="SItr">@assert</span>(value == <span class="SNum">4</span>)
}

<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> value = <span class="SKwd">expect</span> <span class="SFct">count</span>(<span class="SStr">"swag"</span>)
    <span class="SItr">@assert</span>(value == <span class="SNum">4</span>)
}

</span></div>
<h3 id="Defer_on_Error_Paths">Defer on Error Paths</h3>
<p>A plain <span class="code-inline">defer</span> still runs when a function exits through <span class="code-inline">fail</span>, because <span class="code-inline">fail</span> is an early return carrying an error value.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">var</span> <span class="SCst">DeferTrace</span>: <span class="STpe">s32</span> = <span class="SNum">0</span>

<span class="SKwd">func</span> <span class="SFct">deferOnFail</span>(name: <span class="SItr">#null</span> <span class="STpe">string</span>)-&gt;<span class="STpe">u64</span> <span class="SKwd">fail</span>
{
    <span class="SLgc">defer</span> <span class="SCst">DeferTrace</span> += <span class="SNum">1</span>
    <span class="SLgc">return</span> <span class="SKwd">try</span> <span class="SFct">count</span>(name)
}

<span class="SFct">#test</span>
{
    <span class="SCst">DeferTrace</span> = <span class="SNum">0</span>
    <span class="SKwd">let</span> value = <span class="SKwd">catch</span> <span class="SFct">deferOnFail</span>(<span class="SKwd">null</span>) <span class="SLgc">as</span> err
    <span class="SItr">@assert</span>(value == <span class="SNum">0</span>)
    <span class="SItr">@assert</span>(err != <span class="SKwd">null</span>)
    <span class="SItr">@assert</span>(<span class="SCst">DeferTrace</span> == <span class="SNum">1</span>)
}

</span></div>
<h3 id="_013_002_safety_swg">Safety</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Runtime_Safety_Checks">Runtime Safety Checks</h3>
<p>Swag provides safety checks that can be enabled at different granularity levels — module, function, or even individual instruction — via <span class="code-inline">#[Swag.Safety]</span>.</p>
<p>These checks prevent common programming errors by triggering panics during unsafe operations (overflows, invalid math, out-of-bounds access, etc.).</p>
<p>You can also configure safety checks globally from the build configuration with <span class="code-inline">buildCfg.safetyGuards</span>.</p>
<div class="code-block"><span class="SCde">
</span></div>
<div class="blockquote blockquote-note">
<div class="blockquote-title-block"><span class="blockquote-title">Note</span></div>
<p>Swag offers three predefined build configurations: <span class="code-inline">debug</span>, <span class="code-inline">fast-debug</span>, and <span class="code-inline">release</span>. Safety checks are enabled by default in <span class="code-inline">debug</span> and <span class="code-inline">fast-debug</span>, and disabled in <span class="code-inline">release</span> for performance.</p>
</div>
<div class="blockquote blockquote-note">
<div class="blockquote-title-block"><span class="blockquote-title">Note</span></div>
<p>Safety covers the RUNTIME guards. Their static, compile-time counterparts are controlled separately with <span class="code-inline">#[Swag.Sanity]</span> and stay enabled in <span class="code-inline">release</span>; see the dedicated 'Sanity Checks in Swag' section.</p>
</div>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="Overflow_Safety">Overflow Safety</h3>
<p>Example: #[Swag.Safety(.Overflow, true)] When enabled, Swag panics on arithmetic overflow or when bits are lost during integer conversions.</p>
<p>Operators that can overflow include '+ - <i> &lt;&lt; &gt;&gt;' and compound forms '+= -= </i>= &lt;&lt;= &gt;&gt;='.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> x = <span class="SNum">255</span>'<span class="STpe">u8</span>

<span class="SCmt">// x += 1  // Uncomment to see overflow panic</span>
}

</span></div>
<h4 id="Disabling_Overflow_Safety_with___wrap_">Disabling Overflow Safety with <span class="code-inline">#wrap</span></h4>
<p>Use <span class="code-inline">#wrap</span> on the operation if overflow is expected and should not panic.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> x = <span class="SNum">255</span>'<span class="STpe">u8</span>
    x += <span class="SItr">#wrap</span> <span class="SNum">1</span>
    <span class="SItr">@assert</span>(x == <span class="SNum">0</span>)
}

</span></div>
<h4 id="Global_Overflow_Safety_Control">Global Overflow Safety Control</h4>
<p>Disable overflow safety checks in a scope with '#[Swag.Safety(.Overflow, false)]'.</p>
<div class="code-block"><span class="SCde"><span class="SAtr">#[Swag.Safety(.Overflow, false)]</span>
<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> x = <span class="SNum">255</span>'<span class="STpe">u8</span>
    x += <span class="SNum">1</span>
    <span class="SItr">@assert</span>(x == <span class="SNum">0</span>)
}

</span></div>
<h4 id="Promoting_Operations_to_Prevent_Overflow">Promoting Operations to Prevent Overflow</h4>
<p>For 8/16-bit operations, use <span class="code-inline">#prom</span> to promote to 32-bit and avoid overflow.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> x = <span class="SNum">255</span>'<span class="STpe">u8</span> + <span class="SItr">#prom</span> <span class="SNum">1</span>
    <span class="SItr">@assert</span>(x == <span class="SNum">256</span>)
    <span class="SItr">@assert</span>(<span class="SItr">#typeof</span>(x) == <span class="STpe">u32</span>)
}

</span></div>
<h3 id="Information_Loss_During_Casting">Information Loss During Casting</h3>
<p>Swag checks casts for potential information loss between integer types.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> x1 = <span class="SNum">255</span>'<span class="STpe">u8</span>

    <span class="SCmt">// var y0 = cast(s8) x1  // Would panic: 255 not representable as s8</span>

    <span class="SKwd">let</span> y1 = <span class="SKwd">cast</span> <span class="SItr">#wrap</span> (<span class="STpe">s8</span>) x1
    <span class="SItr">@assert</span>(y1 == -<span class="SNum">1</span>)

    <span class="SKwd">let</span> x2 = -<span class="SNum">1</span>'<span class="STpe">s8</span>

    <span class="SCmt">// var y2 = cast(u8) x2  // Would panic: negative to unsigned</span>
    <span class="SKwd">let</span> y2 = <span class="SKwd">cast</span> <span class="SItr">#wrap</span> (<span class="STpe">u8</span>) x2
    <span class="SItr">@assert</span>(y2 == <span class="SNum">255</span>)
}

</span></div>
<h4 id="Disabling_Overflow_Safety_Globally">Disabling Overflow Safety Globally</h4>
<p>Same as above: '#[Swag.Safety(.Overflow, false)]' allows overflowing operations.</p>
<div class="code-block"><span class="SCde"><span class="SAtr">#[Swag.Safety(.Overflow, false)]</span>
<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> x = <span class="SNum">255</span>'<span class="STpe">u8</span>
    x += <span class="SNum">255</span>     <span class="SCmt">// -&gt; 254 (wrap)</span>
    x += <span class="SNum">1</span>       <span class="SCmt">// -&gt; 255</span>
    x &gt;&gt;= <span class="SNum">1</span>      <span class="SCmt">// -&gt; 127</span>
    <span class="SItr">@assert</span>(x == <span class="SNum">127</span>)
}

</span></div>
<h3 id="Dynamic_Cast_Type_Safety">Dynamic Cast Type Safety</h3>
<p>Example: #[Swag.Safety(.DynCast, true)] Swag panics if a cast from <span class="code-inline">any</span> to another type is invalid.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> x: <span class="STpe">any</span> = <span class="SStr">"1"</span>
    <span class="SKwd">let</span> y      = <span class="SKwd">cast</span>(<span class="STpe">string</span>) x

<span class="SCmt">// var z = cast(s32) x  // Would panic: underlying type mismatch</span>
<span class="SCmt">// @assert(z == 0)</span>
}

</span></div>
<p>Swag also panics if casting from an interface to a pointer-to-struct cannot be performed.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="Array_Bounds_Checking">Array Bounds Checking</h3>
<p>Example: #[Swag.Safety(.BoundCheck, true)] Swag panics if an index is out of range when dereferencing sized values (arrays, slices, strings).</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> x   = [<span class="SNum">0</span>, <span class="SNum">1</span>, <span class="SNum">2</span>]
    <span class="SKwd">var</span> idx = <span class="SNum">10</span>

<span class="SCmt">// @assert(x[idx] == 1)  // Would panic: out-of-bounds</span>
}

</span></div>
<h4 id="Safety_When_Indexing_a_Slice">Safety When Indexing a Slice</h4>
<p>Indexing a slice is checked for bounds.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">let</span> x: <span class="SKwd">const</span> [..] <span class="STpe">s32</span> = [<span class="SNum">0</span>, <span class="SNum">1</span>, <span class="SNum">2</span>]
    <span class="SKwd">var</span> idx               = <span class="SNum">1</span>
    <span class="SItr">@assert</span>(x[idx] == <span class="SNum">1</span>)
    idx += <span class="SNum">9</span>

<span class="SCmt">// @assert(x[idx] == 1)  // Would panic: out-of-bounds</span>
}

</span></div>
<h4 id="Safety_When_Slicing_a_Sized_Value">Safety When Slicing a Sized Value</h4>
<p>Slice operations are checked for bounds.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> x: <span class="SKwd">const</span> [..] <span class="STpe">s32</span> = [<span class="SNum">0</span>, <span class="SNum">1</span>, <span class="SNum">2</span>]

<span class="SCmt">// var slice = x[1 to 4]   // Would panic: out-of-bounds</span>
<span class="SCmt">// @assert(slice[0] == 1)</span>
}

<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> x   = <span class="SStr">"string"</span>
    <span class="SKwd">var</span> idx = <span class="SNum">10</span>

<span class="SCmt">// var slice = x[0 to idx] // Would panic: out-of-bounds</span>
<span class="SCmt">// @assert(slice[0] == 's')</span>
}

</span></div>
<h4 id="Safety_on_Loop_Ranges">Safety on Loop Ranges</h4>
<p>A <span class="code-inline">for</span> range whose bounds are not both constant is checked when the loop starts. Swag panics when the lower bound is above the upper bound. An <span class="code-inline">until</span> range whose bounds are equal is empty, not inverted, so it runs zero iterations without panicking.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">func</span> <span class="SFct">sumRange</span>(low, high: <span class="STpe">s32</span>)-&gt;<span class="STpe">s32</span>
    {
        <span class="SKwd">var</span> sum = <span class="SNum">0</span>
        <span class="SLgc">for</span> [i] <span class="SLgc">in</span> low <span class="SLgc">until</span> high <span class="SLgc">do</span>
            sum += i
        <span class="SLgc">return</span> sum
    }

    <span class="SItr">@assert</span>(<span class="SFct">sumRange</span>(<span class="SNum">0</span>, <span class="SNum">0</span>) == <span class="SNum">0</span>)
    <span class="SItr">@assert</span>(<span class="SFct">sumRange</span>(<span class="SNum">2</span>, <span class="SNum">2</span>) == <span class="SNum">0</span>)
    <span class="SItr">@assert</span>(<span class="SFct">sumRange</span>(<span class="SNum">0</span>, <span class="SNum">4</span>) == <span class="SNum">0</span> + <span class="SNum">1</span> + <span class="SNum">2</span> + <span class="SNum">3</span>)

<span class="SCmt">// @assert(sumRange(4, 2) == 0)  // Would panic: lower bound above upper bound</span>
}

</span></div>
<h3 id="Math_Safety">Math Safety</h3>
<p>Example: #[Swag.Safety(.Math, true)] Swag panics for invalid math, such as division by zero or invalid intrinsic arguments.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> x = <span class="SNum">1</span>'<span class="STpe">f32</span>
    <span class="SKwd">var</span> y = <span class="SNum">0</span>'<span class="STpe">f32</span>

<span class="SCmt">// var z = x / y  // Would panic: division by zero</span>
<span class="SCmt">// @print(z)</span>
}

</span></div>
<h4 id="Checking_Invalid_Math_Intrinsic_Arguments">Checking Invalid Math Intrinsic Arguments</h4>
<p>Swag validates arguments for several math intrinsics and panics if invalid.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
<span class="SCmt">// @abs(-128)        // Invalid for abs on this target</span>
<span class="SCmt">// @log(-2'f32)      // Invalid: log of negative</span>
<span class="SCmt">// @log2(-2'f32)     // Invalid: log2 of negative</span>
<span class="SCmt">// @log10(2'f64)     // Example: implementation-specific constraints</span>
<span class="SCmt">// @sqrt(-2'f32)     // Invalid: sqrt of negative</span>
<span class="SCmt">// @asin(-2'f32)     // Invalid: asin out of range</span>
<span class="SCmt">// @acos(2'f32)      // Invalid: acos out of range</span>
}

</span></div>
<h3 id="Switch_Safety">Switch Safety</h3>
<p>Example: #[Swag.Safety(.Switch, true)] Without 'switch #complete', an unmatched value reaches no case and Swag panics.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">enum</span> <span class="SCst">Color</span>
    {
        <span class="SCst">Red</span>
        <span class="SCst">Green</span>
        <span class="SCst">Blue</span>
    }

    <span class="SKwd">func</span> <span class="SFct">colorToString</span>(color: <span class="SCst">Color</span>)-&gt;<span class="STpe">string</span>
    {
        <span class="SCmt">// 'switch #complete' here would reject the missing 'Blue' case at compile time.</span>
        <span class="SLgc">switch</span> color
        {
        <span class="SLgc">case</span> .<span class="SCst">Red</span>:   <span class="SLgc">return</span> <span class="SStr">"Red"</span>
        <span class="SLgc">case</span> .<span class="SCst">Green</span>: <span class="SLgc">return</span> <span class="SStr">"Green"</span>
        }

        <span class="SLgc">return</span> <span class="SStr">""</span>
    }
}

</span></div>
<h3 id="Boolean_Safety">Boolean Safety</h3>
<p>Example: #[Swag.Safety(.Bool, true)] Swag panics if a <span class="code-inline">bool</span> is not <span class="code-inline">true</span> (1) or <span class="code-inline">false</span> (0).</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> b: <span class="STpe">u8</span> = <span class="SNum">2</span>

<span class="SCmt">// if b { }  // Would panic: invalid boolean value</span>
}

</span></div>
<h3 id="NaN_Safety">NaN Safety</h3>
<p>Example: #[Swag.Safety(.NaN, true)] Swag panics if a floating-point <span class="code-inline">NaN</span> participates in an operation, preventing propagation of invalid values.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_013_003_sanity_swg">Sanity</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Static_Sanity_Checks">Static Sanity Checks</h3>
<p>Where <span class="code-inline">#[Swag.Safety]</span> adds <b>runtime</b> guards that panic on invalid operations, <span class="code-inline">#[Swag.Sanity]</span> controls the <b>static</b> checks: analyses that run at compile time and report errors before the program ever runs. They reuse the same <span class="code-inline">SafetyWhat</span> flags, cost nothing at runtime, and can be toggled at the same granularity levels — module, function, or file.</p>
<p>You can also configure them globally from the build configuration with <span class="code-inline">buildCfg.sanityGuards</span>.</p>
<div class="code-block"><span class="SCde">
</span></div>
<div class="blockquote blockquote-note">
<div class="blockquote-title-block"><span class="blockquote-title">Note</span></div>
<p>Sanity checks are enabled by default in every build configuration. This differs from runtime safety, which is disabled in <span class="code-inline">release</span> for performance: the static checks stay on in <span class="code-inline">release</span> since they are free.</p>
</div>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="Proven_Runtime_Faults">Proven Runtime Faults</h3>
<p>The compiler proves some runtime faults statically and reports them as errors instead of letting the (guaranteed) panic or crash happen at runtime: division by a value proven to be zero (<span class="code-inline">.Math</span>), proven integer overflow (<span class="code-inline">.Overflow</span>), dereferencing or calling a pointer proven to be null (<span class="code-inline">.Null</span>), and indexing a stack array with a provably out-of-range constant (<span class="code-inline">.BoundCheck</span>) — free coverage in <span class="code-inline">release</span>, where the runtime guard is off.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> d = <span class="SNum">0</span>
    <span class="SKwd">var</span> a = <span class="SNum">10</span>

    <span class="SCmt">// var x = a / d  // Uncomment: error, division by zero (proven)</span>

    <span class="SKwd">var</span> arr: [<span class="SNum">4</span>] <span class="STpe">s32</span>
    <span class="SKwd">var</span> i = <span class="SNum">5</span>
    arr[<span class="SNum">0</span>] = i

<span class="SCmt">// let y = arr[i]  // Uncomment: error, out-of-bounds access (proven)</span>
}

</span></div>
<h3 id="Returning_the_Address_of_a_Local">Returning the Address of a Local</h3>
<p>The frame dies with the return, so the address of a local is always dangling (<span class="code-inline">.Memory</span>).</p>
<div class="code-block"><span class="SCde"><span class="SKwd">var</span> sanityGlobalValue: <span class="STpe">s32</span>

<span class="SKwd">func</span> <span class="SFct">sanityGlobalAddress</span>()-&gt;*<span class="STpe">s32</span>
{
    <span class="SCmt">// var v: s32</span>
    <span class="SCmt">// return &amp;v  // Uncomment: error, returns the address of a local</span>
    <span class="SLgc">return</span> &amp;sanityGlobalValue     <span class="SCmt">// A global outlives the call</span>
}

</span></div>
<h3 id="Borrow_Escapes">Borrow Escapes</h3>
<p>Views that borrow function-local storage — pointers, slices, strings, <span class="code-inline">any</span>, interfaces, closures capturing by address — must not outlive that storage (<span class="code-inline">.Lifecycle</span>). Returning them, storing them into a global, or writing them through a caller-visible pointer is a compile-time error. This includes views of an OWNER's heap payload (a <span class="code-inline">string</span> view of a local <span class="code-inline">Core.String</span>, for example): the payload is freed when the owner drops, and a local owner drops with its scope.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">var</span> sanityGlobalBuffer: [<span class="SNum">4</span>] <span class="STpe">u8</span>

<span class="SFct">#test</span>
{
    <span class="SKwd">func</span> <span class="SFct">makeView</span>()-&gt;<span class="SKwd">const</span> [..] <span class="STpe">u8</span>
    {
        <span class="SCmt">// var buf: [4] u8</span>
        <span class="SCmt">// return cast(const [..] u8) buf  // Uncomment: error, borrow escapes</span>
        <span class="SLgc">return</span> <span class="SKwd">cast</span>(<span class="SKwd">const</span> [..] <span class="STpe">u8</span>) sanityGlobalBuffer     <span class="SCmt">// A global's storage is fine</span>
    }

    <span class="SItr">@assert</span>(<span class="SItr">@countof</span>(<span class="SFct">makeView</span>()) == <span class="SNum">4</span>)
}

</span></div>
<p>The analysis follows borrows across local bindings — including a call result bound to a local and returned later ('let p = passthrough(&amp;v); return p') — control-flow joins, and even opaque calls: a function whose return value may borrow one of its parameters is summarized, and the call site is checked against what was really passed in. The summaries chain, so wrapping a borrowing function does not hide the borrow, and they cross module boundaries through the generated module API (the <span class="code-inline">Swag.BorrowSummary</span> attribute).</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">func</span> <span class="SFct">passthrough</span>(p: *<span class="STpe">s32</span>)-&gt;*<span class="STpe">s32</span>
    {
        <span class="SLgc">return</span> p
    }

    <span class="SKwd">func</span> <span class="SFct">wrapper</span>(p: *<span class="STpe">s32</span>)-&gt;*<span class="STpe">s32</span>
    {
        <span class="SLgc">return</span> <span class="SFct">passthrough</span>(p)     <span class="SCmt">// Inherits the summary of 'passthrough'</span>
    }

    <span class="SKwd">func</span> <span class="SFct">caller</span>()-&gt;*<span class="STpe">s32</span>
    {
        <span class="SCmt">// var v: s32</span>
        <span class="SCmt">// return wrapper(&amp;v)  // Uncomment: error, borrows a local through the chain</span>
        <span class="SLgc">return</span> <span class="SFct">wrapper</span>(&amp;sanityGlobalValue)     <span class="SCmt">// Caller-owned data flows through</span>
    }

    <span class="SItr">@assert</span>(<span class="SFct">caller</span>() == &amp;sanityGlobalValue)
}

</span></div>
<p>An aggregate can carry several independent borrows. Swag keeps every parameter origin in function summaries and tracks local borrows by field path. Assigning a sibling field therefore neither hides nor inherits another field's borrow. Constant array indices are tracked independently; a dynamic index conservatively overlaps every element. Opaque-call snapshots also survive control-flow joins and compose through arbitrarily deep local call chains.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">struct</span> <span class="SCst">Views</span>
    {
        local:  *<span class="STpe">s32</span>
        global: *<span class="STpe">s32</span>
    }

    <span class="SKwd">var</span> local: <span class="STpe">s32</span>
    <span class="SKwd">var</span> views: <span class="SCst">Views</span> = <span class="SKwd">undefined</span>
    views.local  = &amp;local
    views.global = &amp;sanityGlobalValue
    <span class="SItr">@assert</span>(views.global == &amp;sanityGlobalValue)
}

</span></div>
<h3 id="Stored_Arguments">Stored Arguments</h3>
<p>A callee that stores its parameter into storage that outlives the call (a global) makes any borrowed argument escape, whatever happens to the call result. This summary is inferred like the return summary, chains through wrappers, and crosses module boundaries the same way. Storing one parameter into storage reachable from ANOTHER (<span class="code-inline">container.add(&amp;item)</span>) is summarized as a pair: the call site errors when the container argument is a global and the stored one borrows a local.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">var</span> sanityGlobalStash: <span class="SItr">#null</span> *<span class="STpe">s32</span>

<span class="SKwd">func</span> <span class="SFct">sanityStash</span>(p: *<span class="STpe">s32</span>)
{
    sanityGlobalStash = p     <span class="SCmt">// Legal here: 'p' is caller-owned. Judged at call sites.</span>
}

<span class="SFct">#test</span>
{
    <span class="SKwd">func</span> <span class="SFct">caller</span>()
    {
        <span class="SCmt">// var v: s32</span>
        <span class="SCmt">// sanityStash(&amp;v)  // Uncomment: error, the callee keeps the borrow</span>
        <span class="SFct">sanityStash</span>(&amp;sanityGlobalValue)     <span class="SCmt">// A global outlives everything</span>
    }

    <span class="SFct">caller</span>()
    <span class="SItr">@assert</span>(sanityGlobalStash == &amp;sanityGlobalValue)
}

</span></div>
<h3 id="Use_After_Free_and_Double_Free">Use After Free and Double Free</h3>
<p>Every allocation flows through the <span class="code-inline">Swag.IAllocator</span> interface, whose methods make the operation structural: the analysis infers which functions FREE what their parameters point to (a <span class="code-inline">frees</span> summary, chained through wrappers and across modules like the other summaries). Dereferencing a pointer after it was provably freed — or freeing it twice — is a compile-time error (<span class="code-inline">.Lifecycle</span>). Aliases and conditional frees are misses, never false positives; reassigning the pointer makes it valid again.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">func</span> <span class="SFct">exampleAlloc</span>(size: <span class="STpe">u64</span>)-&gt;<span class="SItr">#null</span> *<span class="STpe">void</span>
    {
        <span class="SKwd">var</span> req: <span class="SCst">Swag</span>.<span class="SCst">AllocatorRequest</span>
        req.size = size
        <span class="SKwd">let</span> allocItf = <span class="SKwd">notnull</span> <span class="SItr">@getcontext</span>().allocator
        allocItf.<span class="SFct">alloc</span>(&amp;req)
        <span class="SLgc">return</span> req.address
    }

    <span class="SKwd">func</span> <span class="SFct">exampleFree</span>(ptr: <span class="SItr">#null</span> *<span class="STpe">void</span>, size: <span class="STpe">u64</span>)
    {
        <span class="SKwd">var</span> req: <span class="SCst">Swag</span>.<span class="SCst">AllocatorRequest</span>
        req.address = ptr
        req.size    = size
        <span class="SKwd">let</span> allocItf = <span class="SKwd">notnull</span> <span class="SItr">@getcontext</span>().allocator
        allocItf.<span class="SFct">free</span>(&amp;req)
    }

    <span class="SKwd">let</span> p = <span class="SKwd">cast</span>(*<span class="STpe">s32</span>) <span class="SKwd">notnull</span> <span class="SFct">exampleAlloc</span>(<span class="SNum">4</span>)
    <span class="SKwd">dref</span> p = <span class="SNum">1</span>
    <span class="SFct">exampleFree</span>(p, <span class="SNum">4</span>)

<span class="SCmt">// let x = dref p       // Uncomment: error, use of a freed pointer (proven)</span>
<span class="SCmt">// exampleFree(p, 4)    // Uncomment: error, the pointer is freed twice (proven)</span>
}

</span></div>
<h3 id="Use_of_Moved-From_Values">Use of Moved-From Values</h3>
<p>Reading a local abandoned by <span class="code-inline">#move</span> or <span class="code-inline">#relocate</span> (and not reset) is a proven error at compile time (<span class="code-inline">.Lifecycle</span>). At runtime, the <span class="code-inline">.Lifecycle</span> <b>safety</b> half additionally poisons abandoned storage with <span class="code-inline">0xDD</span> so the accesses the static check cannot prove still fail deterministically.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">struct</span> <span class="SCst">Item</span>
    {
        x: <span class="STpe">s32</span>
    }

    <span class="SKwd">var</span> a = <span class="SCst">Item</span>{x: <span class="SNum">1</span>}
    <span class="SKwd">var</span> b = <span class="SItr">#move</span> a
    <span class="SItr">@assert</span>(b.x == <span class="SNum">1</span>)

    <span class="SCmt">// @assert(a.x == 1)  // Uncomment: error, use of moved-from value</span>
    a = <span class="SCst">Item</span>{x: <span class="SNum">2</span>}
    <span class="SItr">@assert</span>(a.x == <span class="SNum">2</span>)     <span class="SCmt">// Reassigning makes it readable again</span>
}

</span></div>
<h3 id="Opting_Out">Opting Out</h3>
<p>Like safety, sanity can be disabled per scope with the attribute. Disabling <span class="code-inline">.Lifecycle</span> turns the whole borrow analysis off for that function.</p>
<div class="code-block"><span class="SCde"><span class="SAtr">#[Swag.Sanity(.Lifecycle, false), Swag.Sanity(.Memory, false)]</span>
<span class="SKwd">func</span> <span class="SFct">sanityOptedOut</span>()-&gt;*<span class="STpe">s32</span>
{
    <span class="SKwd">var</span> v: <span class="STpe">s32</span>
    <span class="SLgc">return</span> &amp;v     <span class="SCmt">// Accepted: the analysis is off here</span>
}

</span></div>
<h3 id="The___sanity__Intrinsic">The <span class="code-inline">#sanity</span> Intrinsic</h3>
<p><span class="code-inline">#sanity(...)</span> evaluates, at compile time, whether a given static check is active at this point — the build-config default combined with the <span class="code-inline">Swag.Sanity</span> overrides in scope. It mirrors <span class="code-inline">#safety(...)</span>, which queries the runtime safety flags.</p>
<div class="code-block"><span class="SCde"><span class="SAtr">#[Swag.Sanity(.Lifecycle, false)]</span>
<span class="SFct">#test</span>
{
    <span class="SCmp">#assert</span>(<span class="SItr">#sanity</span>(<span class="SCst">Swag</span>.<span class="SCst">SafetyWhat</span>.<span class="SCst">Lifecycle</span>) == <span class="SKwd">false</span>)
}

</span></div>
<h2 id="_014_000_compile-time_evaluation_swg">Compile-time Evaluation</h2>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>
</span></div>
<h3 id="Compile-Time_Execution">Compile-Time Execution</h3>
<p>Swag reuses the language for compile-time work. Constant expressions evaluate pure computations needed by types and declarations; <span class="code-inline">#run</span> executes arbitrary compile-time code; directives select or validate source; <span class="code-inline">#message</span> observes compiler events.</p>
<p>Compile-time execution can generate runtime declarations, but it is still part of the build. Keep it deterministic, report errors at the source that caused them, and avoid unnecessary filesystem or environment dependencies.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_014_001_constexpr_swg">Constexpr</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Constant-Evaluable_Functions">Constant-Evaluable Functions</h3>
<p><span class="code-inline">#[Swag.ConstExpr]</span> allows a function to participate in a constant expression. When the call and everything it depends on are constant, <span class="code-inline">swc</span> executes it during compilation. A call with runtime arguments remains an ordinary runtime call.</p>
<p>Use this attribute for deterministic computation that belongs in array sizes, constants, static conditions, or generated declarations. Use <span class="code-inline">#run</span> when the operation should execute only as a build-time action.</p>
<div class="code-block"><span class="SCde">
<span class="SAtr">#[Swag.ConstExpr]</span>
<span class="SKwd">func</span> <span class="SFct">constexprSquare</span>(value: <span class="STpe">s32</span>)-&gt;<span class="STpe">s32</span>
{
    <span class="SLgc">return</span> value * value
}

<span class="SKwd">const</span> <span class="SCst">ConstexprSquares</span> = [
    <span class="SFct">constexprSquare</span>(<span class="SNum">1</span>),
    <span class="SFct">constexprSquare</span>(<span class="SNum">2</span>),
    <span class="SFct">constexprSquare</span>(<span class="SNum">3</span>),
    <span class="SFct">constexprSquare</span>(<span class="SNum">4</span>),
    ]

<span class="SCmp">#assert</span>(<span class="SCst">ConstexprSquares</span>[<span class="SNum">0</span>] == <span class="SNum">1</span>)
<span class="SCmp">#assert</span>(<span class="SCst">ConstexprSquares</span>[<span class="SNum">1</span>] == <span class="SNum">4</span>)
<span class="SCmp">#assert</span>(<span class="SCst">ConstexprSquares</span>[<span class="SNum">2</span>] == <span class="SNum">9</span>)
<span class="SCmp">#assert</span>(<span class="SCst">ConstexprSquares</span>[<span class="SNum">3</span>] == <span class="SNum">16</span>)

<span class="SFct">#test</span>
{
    <span class="SKwd">var</span> runtimeValue = <span class="SNum">5</span>
    <span class="SItr">@assert</span>(<span class="SFct">constexprSquare</span>(runtimeValue) == <span class="SNum">25</span>)
}

</span></div>
<h3 id="Branches__Loops__and_Recursion">Branches, Loops, and Recursion</h3>
<p>A constant-evaluable function uses ordinary Swag control flow. Recursive definitions still need a valid base case and are subject to the compiler's execution limits.</p>
<div class="code-block"><span class="SCde">
<span class="SAtr">#[Swag.ConstExpr]</span>
<span class="SKwd">func</span> <span class="SFct">constexprFactorial</span>(value: <span class="STpe">u32</span>)-&gt;<span class="STpe">u32</span>
{
    <span class="SLgc">if</span> value &lt;= <span class="SNum">1</span> <span class="SLgc">do</span>
        <span class="SLgc">return</span> <span class="SNum">1</span>
    <span class="SLgc">return</span> value * <span class="SFct">constexprFactorial</span>(value - <span class="SNum">1</span>)
}

<span class="SAtr">#[Swag.ConstExpr]</span>
<span class="SKwd">func</span> <span class="SFct">constexprSum</span>(values: <span class="SKwd">const</span> [..] <span class="STpe">s32</span>)-&gt;<span class="STpe">s32</span>
{
    <span class="SKwd">var</span> result = <span class="SNum">0</span>
    <span class="SLgc">for</span> value <span class="SLgc">in</span> values <span class="SLgc">do</span>
        result += value
    <span class="SLgc">return</span> result
}

<span class="SCmp">#assert</span>(<span class="SFct">constexprFactorial</span>(<span class="SNum">5</span>) == <span class="SNum">120</span>)
<span class="SCmp">#assert</span>(<span class="SFct">constexprSum</span>([<span class="SNum">1</span>, <span class="SNum">2</span>, <span class="SNum">3</span>, <span class="SNum">4</span>]) == <span class="SNum">10</span>)

</span></div>
<h3 id="Constant_User-Defined_Values">Constant User-Defined Values</h3>
<p>A struct can opt into constant evaluation when its lifecycle operations are valid in that environment. ConstExpr functions may then construct and return instances of that type.</p>
<div class="code-block"><span class="SCde">
<span class="SAtr">#[Swag.ConstExpr]</span>
<span class="SKwd">struct</span> <span class="SCst">ConstexprPoint</span>
{
    x, y: <span class="STpe">s32</span>
}

<span class="SAtr">#[Swag.ConstExpr]</span>
<span class="SKwd">func</span> <span class="SFct">makeConstexprPoint</span>(x, y: <span class="STpe">s32</span>)-&gt;<span class="SCst">ConstexprPoint</span>
{
    <span class="SLgc">return</span> {x, y}
}

<span class="SKwd">const</span> <span class="SCst">ConstexprOrigin</span> = <span class="SFct">makeConstexprPoint</span>(<span class="SNum">3</span>, <span class="SNum">7</span>)
<span class="SCmp">#assert</span>(<span class="SCst">ConstexprOrigin</span>.x == <span class="SNum">3</span>)
<span class="SCmp">#assert</span>(<span class="SCst">ConstexprOrigin</span>.y == <span class="SNum">7</span>)

</span></div>
<h3 id="Static_Conditions_and_Types">Static Conditions and Types</h3>
<p>The result can drive '#static if' or any other context that requires a constant:</p>
<div class="code-block"><span class="SCde">
<span class="SAtr">#[Swag.ConstExpr]</span>
<span class="SKwd">func</span> <span class="SFct">constexprIsPowerOfTwo</span>(value: <span class="STpe">u32</span>)-&gt;<span class="STpe">bool</span>
{
    <span class="SLgc">return</span> value != <span class="SNum">0</span> <span class="SLgc">and</span> (value &amp; (value - <span class="SNum">1</span>)) == <span class="SNum">0</span>
}

<span class="SCmp">#static</span> <span class="SLgc">if</span> !<span class="SFct">constexprIsPowerOfTwo</span>(<span class="SNum">64</span>)
{
    <span class="SCmp">#error</span>(<span class="SStr">"64 must be a power of two"</span>)
}

<span class="SKwd">const</span> <span class="SCst">TableSize</span> = <span class="SFct">constexprFactorial</span>(<span class="SNum">3</span>)
<span class="SKwd">var</span> <span class="SCst">ConstexprSizedTable</span>: [<span class="SCst">TableSize</span>] <span class="STpe">u8</span>
<span class="SCmp">#assert</span>(<span class="SItr">@countof</span>(<span class="SCst">ConstexprSizedTable</span>) == <span class="SNum">6</span>)

</span></div>
<h3 id="Failure_Is_a_Compile-Time_Diagnostic">Failure Is a Compile-Time Diagnostic</h3>
<p>If a constant context calls a <span class="code-inline">ConstExpr</span> function with an operation the compile-time engine cannot perform, the build fails at that call. The compiler does not silently defer a required constant to runtime.</p>
<p>Do not mark a function <span class="code-inline">ConstExpr</span> merely as an optimization hint. The attribute is an API promise that callers may rely on in type-level and declaration-level expressions.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_014_002_run_swg">Run</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Forced_Compile-Time_Execution_with___run_">Forced Compile-Time Execution with <span class="code-inline">#run</span></h3>
<p>The <span class="code-inline">#run</span> directive allows any function to execute at compile time, even if it’s not marked with <span class="code-inline">#[Swag.ConstExpr]</span>. This means you can trigger compile-time execution of regular, external, or system functions as part of your program.</p>
<div class="code-block"><span class="SCde">
<span class="SCmt">// Regular runtime function</span>
<span class="SKwd">func</span> <span class="SFct">isThisRelease</span>() =&gt; <span class="SKwd">true</span>

<span class="SCmt">// Forcing compile-time evaluation with '#run'</span>
<span class="SCmp">#static</span> <span class="SLgc">if</span> <span class="SFct">#run</span> <span class="SFct">isThisRelease</span>() == <span class="SKwd">false</span>
{
    <span class="SCmp">#error</span>(<span class="SStr">"this should not be called!"</span>)
}

</span></div>
<p>Any function — including system or user-defined ones — can be executed at compile time using <span class="code-inline">#run</span>.</p>
<div class="code-block"><span class="SCde">
<span class="SCmt">// Example: sum without 'ConstExpr'</span>
<span class="SKwd">func</span> <span class="SFct">sum</span>(values: <span class="STpe">s32</span>...)-&gt;<span class="STpe">s32</span>
{
    <span class="SKwd">var</span> result = <span class="SNum">0</span>'<span class="STpe">s32</span>
    <span class="SLgc">for</span> v <span class="SLgc">in</span> values <span class="SLgc">do</span>
        result += v
    <span class="SLgc">return</span> result
}

<span class="SCmt">// Force execution at compile time</span>
<span class="SKwd">const</span> <span class="SCst">SumValue</span> = <span class="SFct">#run</span> <span class="SFct">sum</span>(<span class="SNum">1</span>, <span class="SNum">2</span>, <span class="SNum">3</span>, <span class="SNum">4</span>) + <span class="SNum">10</span>
<span class="SCmp">#assert</span>(<span class="SCst">SumValue</span> == <span class="SNum">20</span>)

</span></div>
<h3 id="The___run__Block">The <span class="code-inline">#run</span> Block</h3>
<p><span class="code-inline">#run</span> blocks execute arbitrary logic at compile time. They are useful for initializing globals or precomputing data before runtime.</p>
<p>Execution order between <span class="code-inline">#run</span> blocks is undefined, so avoid relying on order.</p>
<div class="code-block"><span class="SCde">
<span class="SCmt">// Global array initialized at compile time</span>
<span class="SKwd">var</span> <span class="SCst">G</span>: [<span class="SNum">5</span>] <span class="STpe">f32</span> = <span class="SKwd">undefined</span>

<span class="SFct">#run</span>
{
    <span class="SKwd">var</span> value = <span class="SNum">1</span>'<span class="STpe">f32</span>
    <span class="SLgc">for</span> [i] <span class="SLgc">in</span> <span class="SItr">@countof</span>(<span class="SCst">G</span>)
    {
        <span class="SCst">G</span>[i]  = value
        value *= <span class="SNum">2</span>
    }
}

<span class="SCmt">// Validate precomputed results</span>
<span class="SFct">#test</span>
{
    <span class="SItr">@assert</span>(<span class="SCst">G</span>[<span class="SNum">0</span>] == <span class="SNum">1</span>)
    <span class="SItr">@assert</span>(<span class="SCst">G</span>[<span class="SNum">1</span>] == <span class="SNum">2</span>)
    <span class="SItr">@assert</span>(<span class="SCst">G</span>[<span class="SNum">2</span>] == <span class="SNum">4</span>)
    <span class="SItr">@assert</span>(<span class="SCst">G</span>[<span class="SNum">3</span>] == <span class="SNum">8</span>)
    <span class="SItr">@assert</span>(<span class="SCst">G</span>[<span class="SNum">4</span>] == <span class="SNum">16</span>)
}

</span></div>
<p>Swag can act like a scripting language: if a project only contains <span class="code-inline">#run</span> blocks, it behaves like a compile-time script.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="The___run__Expression">The <span class="code-inline">#run</span> Expression</h3>
<p><span class="code-inline">#run</span> can also be used as an expression block. Its return type is inferred from the <span class="code-inline">return</span> statement inside the block.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">const</span> <span class="SCst">Value</span> = <span class="SFct">#run</span>
    {
        <span class="SKwd">var</span> result: <span class="STpe">f32</span>
        <span class="SLgc">for</span> <span class="SNum">10</span> <span class="SLgc">do</span>
            result += <span class="SNum">1</span>
        <span class="SLgc">return</span> result
    }

    <span class="SCmp">#assert</span>(<span class="SCst">Value</span> == <span class="SNum">10.0</span>)
}

</span></div>
<p>Example: initializing a static array at compile time.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">const</span> <span class="SCst">N</span>                   = <span class="SNum">4</span>
    <span class="SKwd">const</span> <span class="SCst">PowerOfTwo</span>: [<span class="SCst">N</span>] <span class="STpe">s32</span> = <span class="SFct">#run</span>
    {
        <span class="SKwd">var</span> arr: [<span class="SCst">N</span>] <span class="STpe">s32</span>
        <span class="SLgc">for</span> [i] <span class="SLgc">in</span> <span class="SItr">@countof</span>(arr) <span class="SLgc">do</span>
            arr[i] = <span class="SNum">1</span> &lt;&lt; <span class="SKwd">cast</span>(<span class="STpe">u32</span>) i
        <span class="SLgc">return</span> arr
    }

    <span class="SCmp">#assert</span>(<span class="SCst">PowerOfTwo</span>[<span class="SNum">0</span>] == <span class="SNum">1</span>)
    <span class="SCmp">#assert</span>(<span class="SCst">PowerOfTwo</span>[<span class="SNum">1</span>] == <span class="SNum">2</span>)
    <span class="SCmp">#assert</span>(<span class="SCst">PowerOfTwo</span>[<span class="SNum">2</span>] == <span class="SNum">4</span>)
    <span class="SCmp">#assert</span>(<span class="SCst">PowerOfTwo</span>[<span class="SNum">3</span>] == <span class="SNum">8</span>)
}

</span></div>
<p>Example: compile-time string construction.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">const</span> <span class="SCst">MyString</span>: <span class="STpe">string</span> = <span class="SFct">#run</span>
    {
        <span class="SKwd">var</span> str: [<span class="SNum">3</span>] <span class="STpe">u8</span>
        str[<span class="SNum">0</span>] = '<span class="SFct">a</span>'
        str[<span class="SNum">1</span>] = '<span class="SFct">b</span>'
        str[<span class="SNum">2</span>] = str[<span class="SNum">1</span>] + <span class="SNum">1</span>
        <span class="SLgc">return</span> <span class="SKwd">cast</span>(<span class="STpe">string</span>) str
    }

    <span class="SCmp">#assert</span>(<span class="SCst">MyString</span> == <span class="SStr">"abc"</span>)
}

</span></div>
<p>Example: initializing a struct in a <span class="code-inline">#run</span> block.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">struct</span> <span class="SCst">RGB</span>
    {
        r, g, b: <span class="STpe">u8</span>
    }

    <span class="SKwd">const</span> <span class="SCst">White</span>: <span class="SCst">RGB</span> = <span class="SFct">#run</span>
    {
        <span class="SKwd">var</span> rgb: <span class="SCst">RGB</span> = <span class="SKwd">undefined</span>
        rgb.r = <span class="SNum">255</span>
        rgb.g = rgb.r
        rgb.b = rgb.r
        <span class="SLgc">return</span> rgb
    }

    <span class="SItr">@assert</span>(<span class="SCst">White</span>.r == <span class="SNum">255</span> <span class="SLgc">and</span> <span class="SCst">White</span>.g == <span class="SNum">255</span> <span class="SLgc">and</span> <span class="SCst">White</span>.b == <span class="SNum">255</span>)
}

</span></div>
<div class="blockquote blockquote-note">
<div class="blockquote-title-block"><span class="blockquote-title">Note</span></div>
<p>Complex structs that implement <span class="code-inline">opCount</span> and <span class="code-inline">opSlice</span> can be converted to static arrays at compile time. The compiler calls <span class="code-inline">opCount</span> for array size, <span class="code-inline">opSlice</span> for initialization, and <span class="code-inline">opDrop</span> after conversion if present.</p>
</div>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_014_003_compiler_instructions_swg">Compiler Instructions</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SLgc">if</span> <span class="SKwd">true</span>
<span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="The___assert__Directive">The <span class="code-inline">#assert</span> Directive</h3>
<p>The <span class="code-inline">#assert</span> directive performs a static assertion during compilation. If the condition is false, compilation fails with an error message. Use it to enforce compile-time invariants and validate assumptions.</p>
<div class="code-block"><span class="SCde"><span class="SCmp">#assert</span>(<span class="SKwd">true</span>)     <span class="SCmt">// Always passes; no error.</span>

</span></div>
<h3 id="The___defined__Query">The <span class="code-inline">#defined</span> Query</h3>
<p><span class="code-inline">#defined(SYMBOL)</span> checks at compile time whether a symbol exists in the current context. It returns true if defined, false otherwise. Useful for conditional compilation before referencing variables, constants, or functions.</p>
<div class="code-block"><span class="SCde"><span class="SCmp">#assert</span>(!<span class="SItr">#defined</span>(<span class="SCst">DOES_NOT_EXISTS</span>))     <span class="SCmt">// Ensure the symbol is not defined.</span>
<span class="SCmp">#assert</span>(<span class="SItr">#defined</span>(<span class="SCst">Global</span>))               <span class="SCmt">// Confirms 'Global' is defined.</span>
<span class="SKwd">var</span> <span class="SCst">Global</span> = <span class="SNum">0</span>                          <span class="SCmt">// Define a global variable 'Global'.</span>

</span></div>
<h3 id="Static_Control_with___static_">Static Control with <span class="code-inline">#static</span></h3>
<p><span class="code-inline">#static</span> applies compile-time semantics to the control statement that follows. The condition or selected value is evaluated at compile time, and only the selected branch is retained. The ordinary <span class="code-inline">elif</span> and <span class="code-inline">else</span> keywords complete a static <span class="code-inline">if</span>; they do not repeat the <span class="code-inline">#static</span> prefix.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">const</span> <span class="SCst">DEBUG</span>   = <span class="SNum">1</span>
<span class="SKwd">const</span> <span class="SCst">RELEASE</span> = <span class="SNum">0</span>

<span class="SCmp">#static</span> <span class="SLgc">if</span> <span class="SCst">DEBUG</span>
{
<span class="SCmt">// Compiled because DEBUG == 1.</span>
}
<span class="SLgc">elif</span> <span class="SCst">RELEASE</span>
{
<span class="SCmt">// Would compile if RELEASE were true and DEBUG were false.</span>
}
<span class="SLgc">else</span>
{
<span class="SCmt">// Compiled if neither DEBUG nor RELEASE is true.</span>
}

</span></div>
<p>'#static switch' selects one section from a compile-time value. Multiple values can share a section, and <span class="code-inline">default</span> is optional. Unlike a runtime <span class="code-inline">switch</span>, this construct does not create runtime control flow and does not use <span class="code-inline">break</span> or <span class="code-inline">fallthrough</span>.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">enum</span> <span class="SCst">StaticBuildMode</span>
{
    <span class="SCst">Debug</span>
    <span class="SCst">Release</span>
}

<span class="SKwd">const</span> <span class="SCst">StaticMode</span> = <span class="SCst">StaticBuildMode</span>.<span class="SCst">Release</span>

<span class="SCmp">#static</span> <span class="SLgc">switch</span> <span class="SCst">StaticMode</span>
{
<span class="SLgc">case</span> .<span class="SCst">Debug</span>:   <span class="SCmp">#error</span>(<span class="SStr">"debug mode is not selected"</span>)
<span class="SLgc">case</span> .<span class="SCst">Release</span>: <span class="SKwd">const</span> <span class="SCst">StaticSelection</span> = <span class="SNum">42</span>
<span class="SLgc">default</span>:       <span class="SCmp">#error</span>(<span class="SStr">"unknown build mode"</span>)
}

<span class="SCmp">#assert</span>(<span class="SCst">StaticSelection</span> == <span class="SNum">42</span>)

</span></div>
<p>Add <span class="code-inline">#complete</span> to require the sections to cover every declared value of an enum. As for a runtime <span class="code-inline">switch</span>, a missing value is an error and a <span class="code-inline">default</span> is then rejected, because there is nothing left for it to catch.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">const</span> <span class="SCst">StaticExhaustive</span> = <span class="SCst">StaticBuildMode</span>.<span class="SCst">Debug</span>

<span class="SCmp">#static</span> <span class="SLgc">switch</span> <span class="SItr">#complete</span> <span class="SCst">StaticExhaustive</span>
{
<span class="SLgc">case</span> .<span class="SCst">Debug</span>:   <span class="SKwd">const</span> <span class="SCst">StaticExhaustiveSelection</span> = <span class="SNum">1</span>
<span class="SLgc">case</span> .<span class="SCst">Release</span>: <span class="SKwd">const</span> <span class="SCst">StaticExhaustiveSelection</span> = <span class="SNum">2</span>
}

<span class="SCmp">#assert</span>(<span class="SCst">StaticExhaustiveSelection</span> == <span class="SNum">1</span>)

</span></div>
<h3 id="The___command__and___cfg__Values">The <span class="code-inline">#command</span> and <span class="code-inline">#cfg</span> Values</h3>
<p><span class="code-inline">#command</span> reports one of three source-compilation modes:</p>
<ul>
<li><span class="code-inline">Swag.CompilerCommand.Test</span> for 'swc test';</li>
<li><span class="code-inline">Swag.CompilerCommand.Format</span> for 'swc format';</li>
<li><span class="code-inline">Swag.CompilerCommand.Build</span> for <span class="code-inline">build</span>, <span class="code-inline">run</span>, <span class="code-inline">syntax</span>, <span class="code-inline">sema</span>, and the</li>
</ul>
<p>compiler-internal <span class="code-inline">unittest</span> path.</p>
<p><span class="code-inline">#cfg</span> is the selected build-configuration name, such as <span class="code-inline">"fast-debug"</span> or <span class="code-inline">"release"</span>. Use these values for genuine source differences, not as a replacement for safety and optimization attributes.</p>
<div class="code-block"><span class="SCde"><span class="SCmp">#static</span> <span class="SLgc">if</span> <span class="SCmp">#command</span> == <span class="SCst">Swag</span>.<span class="SCst">CompilerCommand</span>.<span class="SCst">Test</span>
{
    <span class="SCmt">// Test-only declarations.</span>
}

<span class="SCmp">#static</span> <span class="SLgc">if</span> <span class="SCmp">#cfg</span> == <span class="SStr">"release"</span>
{
    <span class="SCmt">// Release-specific declarations.</span>
}
</span></div>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="The___error__and___warning__Directives">The <span class="code-inline">#error</span> and <span class="code-inline">#warning</span> Directives</h3>
<p><span class="code-inline">#error</span> raises a compile-time error with a custom message. <span class="code-inline">#warning</span> emits a compile-time warning without stopping compilation. Useful for enforcing checks and surfacing build-time information.</p>
<div class="code-block"><span class="SCde"><span class="SCmp">#static</span> <span class="SLgc">if</span> <span class="SKwd">false</span>
{
    <span class="SCmp">#error</span>(<span class="SStr">"this is an error"</span>)        <span class="SCmt">// Compile-time error (if reached).</span>
    <span class="SCmp">#warning</span>(<span class="SStr">"this is a warning"</span>)     <span class="SCmt">// Compile-time warning (if reached).</span>
}

</span></div>
<h3 id="The___global__Directive">The <span class="code-inline">#global</span> Directive</h3>
<p>Place <span class="code-inline">#global</span> at the top of a source file to apply global settings or attributes across the entire file. Controls compilation and symbol visibility.</p>
<p>Examples (write these as top-level directives): #global if false            // Skip file content. #global if #command == Swag.CompilerCommand.Format // Include this file only when formatting. #global if #command == Swag.CompilerCommand.Test   // Include this file only when running tests. #global public                      // All symbols become public. #global private                    // All symbols are private to the module. #global namespace Toto              // Place all symbols in namespace <span class="code-inline">Toto</span>. #global if DEBUG == true     // Conditional compilation for the file. #global #[Swag.Safety(.All, true)]  // Apply an attribute to all declarations. #global export                      // Export the full file as-is into the module API output.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="The___foreignlib__Directive">The <span class="code-inline">#foreignlib</span> Directive</h3>
<p>Register an external import library with the native linker. Pass the logical library name without a platform extension; the linker selects the appropriate file for the active toolchain.</p>
<p>Example: #foreignlib("kernel32")</p>
<p>This directive only supplies the native link dependency. Declare imported symbols separately with <span class="code-inline">#[Swag.Foreign]</span>.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_014_004_code_inspection_swg">Code Inspection</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Code_Inspection">Code Inspection</h3>
<p><span class="code-inline">#message</span> registers a compile-time handler for compiler events. Inside the handler, <span class="code-inline">@compiler.getMessage()</span> describes the event and <span class="code-inline">@compiler.compileString()</span> adds generated Swag source to the current module.</p>
<p>Use the narrowest message mask possible. Per-symbol masks such as <span class="code-inline">SemFunctions</span> may run many times; pass masks such as <span class="code-inline">PassAfterSemantic</span> run once for the module.</p>
<div class="code-block"><span class="SCde">
<span class="SKwd">internal</span> <span class="SKwd">var</span> <span class="SCst">CodeInspectionHookRan</span> = <span class="SKwd">false</span>

<span class="SFct">#message</span>(<span class="SCst">Swag</span>.<span class="SCst">CompilerMsgMask</span>.<span class="SCst">PassAfterSemantic</span>)
{
    <span class="SKwd">let</span> itf = <span class="SItr">@compiler</span>
    <span class="SKwd">let</span> msg = <span class="SKwd">notnull</span> itf.<span class="SFct">getMessage</span>()

    <span class="SLgc">if</span> msg.kind != <span class="SCst">Swag</span>.<span class="SCst">CompilerMsgKind</span>.<span class="SCst">PassAfterSemantic</span> <span class="SLgc">do</span>
        <span class="SLgc">return</span>
    itf.<span class="SFct">compileString</span>(<span class="SStr">"#init { CodeInspectionHookRan = true }\n"</span>)
}

<span class="SFct">#test</span>
{
    <span class="SItr">@assert</span>(<span class="SCst">CodeInspectionHookRan</span>)
}

</span></div>
<p>The message payload depends on its <span class="code-inline">kind</span>:</p>
<ul>
<li><span class="code-inline">SemFunctions</span> provides the function name and a <span class="code-inline">TypeInfoFunc</span>.</li>
<li><span class="code-inline">SemTypes</span> provides a reflected type.</li>
<li><span class="code-inline">SemGlobals</span> provides a global name and type.</li>
<li>pass events identify a compilation phase rather than one declaration.</li>
</ul>
<p>Always check nullable payload fields before dereferencing them in a handler that subscribes to more than one event kind.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h2 id="_015_000_metaprogramming_swg">Metaprogramming</h2>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>
</span></div>
<h3 id="Metaprogramming">Metaprogramming</h3>
<p>Swag can transform code at the call site with mixins and macros, inject source from <span class="code-inline">#ast</span>, or add module-wide declarations through the compiler interface.</p>
<p>Prefer the narrowest mechanism that fits the job: a generic for type-safe reuse, a macro for caller-context expressions, a mixin for injected statements or declarations, <span class="code-inline">#ast</span> for local generated syntax, and <span class="code-inline">compileString</span> for event-driven module generation.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_015_001_mixins_swg">Mixins</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Mixins">Mixins</h3>
<p>A mixin in Swag is declared similarly to a function but with the attribute <span class="code-inline">#[Swag.Mixin]</span>. Mixins inject code into the caller's scope, manipulate variables, or execute as if written in that scope. This file provides a clear set of examples and tests.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SAtr">#[Swag.Mixin]</span>
    <span class="SKwd">func</span> <span class="SFct">myMixin</span>()
    {
    <span class="SCmt">// Basic empty mixin</span>
    }
}

</span></div>
<h3 id="Basic_Example_of_a_Mixin">Basic Example of a Mixin</h3>
<p>A mixin can directly modify variables in the caller's scope. This example increments <span class="code-inline">a</span> by 1 each time it is called.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SAtr">#[Swag.Mixin]</span>
    <span class="SKwd">func</span> <span class="SFct">myMixin</span>()
    {
        a += <span class="SNum">1</span>
    }

    <span class="SKwd">var</span> a = <span class="SNum">0</span>
    <span class="SFct">myMixin</span>()     <span class="SCmt">// Equivalent to writing 'a += 1' directly here</span>
    <span class="SFct">myMixin</span>()
    <span class="SItr">@assert</span>(a == <span class="SNum">2</span>)
}

</span></div>
<h3 id="Mixins_with_Parameters">Mixins with Parameters</h3>
<p>Mixins behave like functions: they can take parameters, default values, and return values. Here, <span class="code-inline">increment</span> defaults to 1.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SAtr">#[Swag.Mixin]</span>
    <span class="SKwd">func</span> <span class="SFct">myMixin</span>(increment: <span class="STpe">s32</span> = <span class="SNum">1</span>)
    {
        a += increment
    }

    <span class="SKwd">var</span> a = <span class="SNum">0</span>
    <span class="SFct">myMixin</span>()      <span class="SCmt">// Uses default: 'a += 1'</span>
    <span class="SFct">myMixin</span>(<span class="SNum">2</span>)     <span class="SCmt">// Uses provided value: 'a += 2'</span>
    <span class="SItr">@assert</span>(a == <span class="SNum">3</span>)
}

</span></div>
<h3 id="Mixins_with_Code_Blocks">Mixins with Code Blocks</h3>
<p>A mixin can accept a <span class="code-inline">#code</span> parameter, representing a Swag code block defined at the call site. The mixin can execute this block multiple times using <span class="code-inline">#inject</span>.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SAtr">#[Swag.Mixin]</span>
    <span class="SKwd">func</span> <span class="SFct">doItTwice</span>(what: <span class="SItr">#code</span>)
    {
        <span class="SCmp">#inject</span>(what)

        <span class="SCmt">// first execution</span>
        <span class="SCmp">#inject</span>(what)

    <span class="SCmt">// second execution</span>
    }

    <span class="SKwd">var</span> a = <span class="SNum">0</span>
    <span class="SFct">doItTwice</span>(<span class="SItr">#code</span> {
        a += <span class="SNum">1</span>
    })
    <span class="SItr">@assert</span>(a == <span class="SNum">2</span>)
}

</span></div>
<h3 id="Passing_Code_Blocks_in_Separate_Statements">Passing Code Blocks in Separate Statements</h3>
<p>When the last parameter is a <span class="code-inline">#code</span> statement block, the code can be provided in a separate block after the call.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SAtr">#[Swag.Mixin]</span>
    <span class="SKwd">func</span> <span class="SFct">doItTwice</span>(value: <span class="STpe">s32</span>, what: <span class="SItr">#code</span>)
    {
        <span class="SCmp">#inject</span>(what)
        <span class="SCmp">#inject</span>(what)
    }

    <span class="SKwd">var</span> a = <span class="SNum">0</span>

    <span class="SCmt">// Inline code argument</span>
    <span class="SFct">doItTwice</span>(<span class="SNum">4</span>, <span class="SItr">#code</span> {
        a += value
    })

    <span class="SCmt">// Separate trailing block</span>
    <span class="SFct">doItTwice</span>(<span class="SNum">2</span>)
    {
        a += value
    }

    <span class="SItr">@assert</span>(a == <span class="SNum">12</span>)
}

</span></div>
<h3 id="Mixins_with_Block_Parameters">Mixins with Block Parameters</h3>
<p>Like macros, a mixin's <span class="code-inline">#code</span> parameter can declare named block parameters, bound by <span class="code-inline">#inject</span>. Since a mixin already runs in the caller's scope, the bindings are plain declarations there.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SAtr">#[Swag.Mixin]</span>
    <span class="SKwd">func</span> <span class="SFct">inc10</span>(stmt: <span class="SItr">#code</span>(cell))
    {
        <span class="SCmp">#inject</span>(stmt, cell = <span class="SNum">10</span>)
    }

    <span class="SKwd">var</span> a, b = <span class="SNum">0</span>
    <span class="SFct">inc10</span>()
    {
        a += cell
    }

    <span class="SFct">inc10</span>() <span class="SItr">#code</span>(amount) {
        b += amount
    }

    <span class="SItr">@assert</span>(a == b <span class="SLgc">and</span> b == <span class="SNum">10</span>)
}

</span></div>
<h3 id="Unique_Variable_Names_with___uniq0__through___uniq9_">Unique Variable Names with <span class="code-inline">#uniq0</span> through <span class="code-inline">#uniq9</span></h3>
<p>Mixins can declare special variables named <span class="code-inline">#uniq0</span> through <span class="code-inline">#uniq9</span>. Each invocation receives unique symbols, avoiding naming conflicts and allowing multiple calls in the same scope. Reusing the same numbered name inside one invocation refers to that invocation's generated symbol.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> total: <span class="STpe">s32</span>

    <span class="SAtr">#[Swag.Mixin]</span>
    <span class="SKwd">func</span> <span class="SFct">toScope</span>()
    {
        <span class="SKwd">var</span> <span class="SItr">#uniq0</span>: <span class="STpe">s32</span> = <span class="SNum">1</span>
        total += <span class="SItr">#uniq0</span>
    }

    <span class="SFct">toScope</span>()
    <span class="SFct">toScope</span>()
    <span class="SFct">toScope</span>()

    <span class="SItr">@assert</span>(total == <span class="SNum">3</span>)
}

</span></div>
<h3 id="_015_002_macros_swg">Macros</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Macros">Macros</h3>
<p>Macros in Swag are declared like functions, but with the <span class="code-inline">#[Swag.Macro]</span> attribute. They are expanded at compile time and can be reused to generate code.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SAtr">#[Swag.Macro]</span>
    <span class="SKwd">func</span> <span class="SFct">myMacro</span>() {}
}

</span></div>
<h3 id="Macro_Scope">Macro Scope</h3>
<p>Macros run in their own scope, isolated from the caller. Unlike mixins, they do not share the caller's scope. Variables defined inside a macro cannot interfere with the caller unless explicitly elevated.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SAtr">#[Swag.Macro]</span>
    <span class="SKwd">func</span> <span class="SFct">myMacro</span>()
    {
        <span class="SCmt">// 'a' here is local to the macro</span>
        <span class="SKwd">var</span> a = <span class="SNum">666</span>
    }

    <span class="SKwd">let</span> a = <span class="SNum">0</span>
    <span class="SFct">myMacro</span>()     <span class="SCmt">// no conflict with outer 'a'</span>
    <span class="SItr">@assert</span>(a == <span class="SNum">0</span>)
}

</span></div>
<h3 id="Macros_with___code__Parameters">Macros with <span class="code-inline">#code</span> Parameters</h3>
<p>A <span class="code-inline">#code</span> parameter declares like a function, with <span class="code-inline">func</span> replaced by <span class="code-inline">#code</span>:</p>
<ul>
<li><span class="code-inline">#code</span> alone is a statement block.</li>
<li><span class="code-inline">#code-&gt;T</span> is an expression block of type T.</li>
<li>'#code(a, b: T)' declares named block parameters (types are optional).</li>
</ul>
<p><span class="code-inline">#inject</span> inserts the caller-provided code at the injection point. Injected code is hygienic: it resolves in the caller's scope, and cannot see the macro's own locals.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SAtr">#[Swag.Macro]</span>
    <span class="SKwd">func</span> <span class="SFct">myMacro</span>(what: <span class="SItr">#code</span>)
    {
        <span class="SCmp">#inject</span>(what)     <span class="SCmt">// insert provided code</span>
    }

    <span class="SKwd">var</span> a = <span class="SNum">0</span>

    <span class="SCmt">// Use '#code' to pass a block as code (not evaluated at call site)</span>
    <span class="SFct">myMacro</span>(<span class="SItr">#code</span> {
        a += <span class="SNum">1</span>
    })

    <span class="SCmt">// If the last parameter is a '#code' statement block, the following statement</span>
    <span class="SCmt">// becomes the last argument</span>
    <span class="SFct">myMacro</span>()
    {
        a += <span class="SNum">1</span>
    }

    <span class="SItr">@assert</span>(a == <span class="SNum">2</span>)
}

</span></div>
<h3 id="Expression___code__Parameters">Expression <span class="code-inline">#code</span> Parameters</h3>
<p>Use <span class="code-inline">#code-&gt;T</span> for a code expression that returns a specific type. The expression is evaluated at each <span class="code-inline">#inject</span>, not at the call site. '#code =&gt; expr' is the explicit expression literal, mirroring the short function form 'func() =&gt; expr'.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SAtr">#[Swag.Macro]</span>
    <span class="SKwd">func</span> <span class="SFct">myMacro</span>(what: <span class="SItr">#code</span>-&gt;<span class="STpe">bool</span>)
    {
        <span class="SItr">@assert</span>(<span class="SCmp">#inject</span>(what))
    }

    <span class="SCmt">// A plain expression argument converts to code implicitly</span>
    <span class="SFct">myMacro</span>(<span class="SNum">1</span> == <span class="SNum">1</span>)
    <span class="SFct">myMacro</span>(<span class="SNum">3</span> &gt; <span class="SNum">2</span> <span class="SLgc">and</span> <span class="SNum">2</span> &lt; <span class="SNum">4</span>)
    <span class="SFct">myMacro</span>(<span class="SKwd">true</span>)

    <span class="SCmt">// The explicit literal form</span>
    <span class="SFct">myMacro</span>(<span class="SItr">#code</span> =&gt; <span class="SKwd">true</span>)
}

</span></div>
<h3 id="Injection_Hygiene">Injection Hygiene</h3>
<p>Injected code always resolves in the caller's scope: a macro-local variable never shadows a caller variable used by the injected block.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SAtr">#[Swag.Macro]</span>
    <span class="SKwd">func</span> <span class="SFct">myMacro</span>(what: <span class="SItr">#code</span>)
    {
        <span class="SKwd">var</span> a = <span class="SNum">666</span>     <span class="SCmt">// macro-local 'a', invisible to the injected code</span>

        <span class="SCmp">#inject</span>(what)
    }

    <span class="SKwd">var</span> a = <span class="SNum">1</span>
    <span class="SFct">myMacro</span>()
    {
        a += <span class="SNum">2</span>     <span class="SCmt">// operates on the caller's 'a'</span>
    }

    <span class="SItr">@assert</span>(a == <span class="SNum">3</span>)
}

</span></div>
<h3 id="Declared_Block_Parameters">Declared Block Parameters</h3>
<p>The <span class="code-inline">#code(...)</span> parameter names are the macro's contract: <span class="code-inline">#inject</span> binds them by name, and the injected code sees the resulting values under those names. Binding initializers evaluate in the macro's own scope, so no <span class="code-inline">#up</span> or <span class="code-inline">#macro</span> wrapping is needed.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SAtr">#[Swag.Macro]</span>
    <span class="SKwd">func</span> <span class="SFct">call</span>(v: <span class="STpe">s32</span>, stmt: <span class="SItr">#code</span>(value: <span class="STpe">s32</span>, double: <span class="STpe">s32</span>))
    {
        <span class="SCmp">#inject</span>(stmt, value = v, double = v * <span class="SNum">2</span>)
    }

    <span class="SCmt">// The declared names are visible at the call site by default.</span>
    <span class="SFct">call</span>(<span class="SNum">20</span>)
    {
        <span class="SItr">@assert</span>(value == <span class="SNum">20</span>)
        <span class="SItr">@assert</span>(double == <span class="SNum">40</span>)
    }
}

</span></div>
<h3 id="Renaming_Block_Parameters_at_the_Call_Site">Renaming Block Parameters at the Call Site</h3>
<p>The caller can rename the block parameters positionally with a <span class="code-inline">#code(...)</span> literal placed before the block. The same literal works inline, as a regular argument.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SAtr">#[Swag.Macro]</span>
    <span class="SKwd">func</span> <span class="SFct">call</span>(v: <span class="STpe">s32</span>, stmt: <span class="SItr">#code</span>(value: <span class="STpe">s32</span>, double: <span class="STpe">s32</span>))
    {
        <span class="SCmp">#inject</span>(stmt, value = v, double = v * <span class="SNum">2</span>)
    }

    <span class="SKwd">var</span> total = <span class="SNum">0</span>

    <span class="SCmt">// Trailing form: the binder renames 'value' to 'x' and 'double' to 'y'.</span>
    <span class="SFct">call</span>(<span class="SNum">20</span>) <span class="SItr">#code</span>(x, y) {
        total = x + y
    }

    <span class="SItr">@assert</span>(total == <span class="SNum">60</span>)

    <span class="SCmt">// Inline form: the code literal is a normal argument.</span>
    <span class="SFct">call</span>(<span class="SNum">10</span>, <span class="SItr">#code</span>(a, b) {
        total = a + b
    })
    <span class="SItr">@assert</span>(total == <span class="SNum">30</span>)

    <span class="SCmt">// Partial binder: only the first parameter is renamed, like 'for'.</span>
    <span class="SFct">call</span>(<span class="SNum">5</span>) <span class="SItr">#code</span>(first) {
        total = first + double
    }

    <span class="SItr">@assert</span>(total == <span class="SNum">15</span>)
}

</span></div>
<h3 id="Mutable_Block_Parameters">Mutable Block Parameters</h3>
<p>A <span class="code-inline">var</span> parameter gives the injected code a mutable binding. A typed parameter also types (and checks) the binding, which is required for references.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SAtr">#[Swag.Macro]</span>
    <span class="SKwd">func</span> <span class="SFct">withCounter</span>(start: <span class="STpe">s32</span>, stmt: <span class="SItr">#code</span>(<span class="SKwd">var</span> counter: <span class="STpe">s32</span>))
    {
        <span class="SCmp">#inject</span>(stmt, counter = start)
    }

    <span class="SKwd">var</span> got = <span class="SNum">0</span>
    <span class="SFct">withCounter</span>(<span class="SNum">10</span>)
    {
        counter += <span class="SNum">5</span>
        got     = counter
    }

    <span class="SItr">@assert</span>(got == <span class="SNum">15</span>)
}

</span></div>
<h3 id="Performance_Considerations_with_Macros">Performance Considerations with Macros</h3>
<p>Macros extend the language without function-pointer/lambda overhead. They can be used to generate tight loops with caller-visible indices, etc.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SAtr">#[Swag.Macro]</span>
    <span class="SKwd">func</span> <span class="SFct">repeat</span>(count: <span class="STpe">s32</span>, what: <span class="SItr">#code</span>(index: <span class="STpe">s32</span>))
    {
        <span class="SKwd">var</span> a = <span class="SNum">0</span>
        <span class="SLgc">while</span> a &lt; count
        {
            <span class="SCmp">#inject</span>(what, index = a)
            a += <span class="SNum">1</span>
        }
    }

    <span class="SKwd">var</span> a = <span class="SNum">0</span>
    <span class="SFct">repeat</span>(<span class="SNum">5</span>)
    {
        a += index     <span class="SCmt">// sum 0..4</span>
    }

    <span class="SItr">@assert</span>(a == <span class="SNum">0</span> + <span class="SNum">1</span> + <span class="SNum">2</span> + <span class="SNum">3</span> + <span class="SNum">4</span>)

    <span class="SFct">repeat</span>(<span class="SNum">3</span>)
    {
        a += index     <span class="SCmt">// add 0..2</span>
    }

    <span class="SItr">@assert</span>(a == <span class="SNum">10</span> + <span class="SNum">3</span>)
}

</span></div>
<h3 id="Handling__break__and__continue__in_User_Code_with_Macros">Handling <span class="code-inline">break</span> and <span class="code-inline">continue</span> in User Code with Macros</h3>
<p>You can remap <span class="code-inline">break</span>/<span class="code-inline">continue</span> in injected user code to control which loop they target. Bindings and control-flow replacements live in the same <span class="code-inline">#inject</span>.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SAtr">#[Swag.Macro]</span>
    <span class="SKwd">func</span> <span class="SFct">repeatSquare</span>(count: <span class="STpe">u32</span>, what: <span class="SItr">#code</span>)
    {
        <span class="SCmt">// Define a scope label used as the break target</span>
        <span class="SCmp">#scope</span>(<span class="SCst">ScopeTarget</span>)

            <span class="SLgc">for</span> count
        {
            <span class="SLgc">for</span> count
            {
                <span class="SCmt">// Remap 'break' in user code to 'break to ScopeTarget' (outer loop exit)</span>
                <span class="SCmp">#inject</span>(what, <span class="SLgc">break</span> = <span class="SLgc">break</span> <span class="SLgc">to</span> <span class="SCst">ScopeTarget</span>)
            }
        }
    }

    <span class="SKwd">var</span> a = <span class="SNum">0</span>

    <span class="SFct">repeatSquare</span>(<span class="SNum">5</span>)
    {
        a += <span class="SNum">1</span>
        <span class="SLgc">if</span> a == <span class="SNum">10</span> <span class="SLgc">do</span>
            <span class="SLgc">break</span>     <span class="SCmt">// remapped to 'break to ScopeTarget'</span>
    }

    <span class="SItr">@assert</span>(a == <span class="SNum">10</span>)
}

</span></div>
<h4 id="Another_example_">Another example:</h4>
<p>Remap both <span class="code-inline">break</span> and <span class="code-inline">continue</span> to influence outer/inner loop flow.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SAtr">#[Swag.Macro]</span>
    <span class="SKwd">func</span> <span class="SFct">repeatSquare</span>(count: <span class="STpe">u32</span>, what: <span class="SItr">#code</span>)
    {
        <span class="SCmt">// Label for controlling the outer loop</span>
        <span class="SCmp">#scope</span>(<span class="SCst">Outer</span>)

            <span class="SLgc">for</span> count
        {
            <span class="SLgc">for</span> count
            {
                <span class="SCmt">// 'break' -&gt; exit outer loop; 'continue' -&gt; skip inner iteration</span>
                <span class="SCmp">#inject</span>(what, <span class="SLgc">break</span> = <span class="SLgc">break</span> <span class="SLgc">to</span> <span class="SCst">Outer</span>, <span class="SLgc">continue</span> = <span class="SLgc">break</span>)
            }
        }
    }

    <span class="SKwd">var</span> a = <span class="SNum">0</span>
    <span class="SKwd">var</span> b = <span class="SNum">0</span>

    <span class="SFct">repeatSquare</span>(<span class="SNum">5</span>)
    {
        a += <span class="SNum">1</span>

        <span class="SCmt">// If 'a' divisible by 3, skip to next inner iteration (acts like 'continue')</span>
        <span class="SLgc">if</span> a % <span class="SNum">3</span> == <span class="SNum">0</span> <span class="SLgc">do</span>
            <span class="SLgc">continue</span>

        b += <span class="SNum">1</span>

        <span class="SCmt">// Exit both loops when 'a' reaches 8</span>
        <span class="SLgc">if</span> a == <span class="SNum">8</span> <span class="SLgc">do</span>
            <span class="SLgc">break</span>
    }

    <span class="SItr">@assert</span>(a == <span class="SNum">8</span>)
    <span class="SItr">@assert</span>(b == <span class="SNum">6</span>)
}

</span></div>
<h3 id="_015_003_generated_code_with_ast_swg">Generated Code with Ast</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="The___ast__Block">The <span class="code-inline">#ast</span> Block</h3>
<p>The <span class="code-inline">#ast</span> block lets you dynamically generate and inject Swag code at compile time. It produces a string that the compiler treats as if it were written directly in the source. This allows for dynamic, context-dependent code generation.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="Basic___ast__Usage">Basic <span class="code-inline">#ast</span> Usage</h3>
<p>A <span class="code-inline">#ast</span> block can return a simple string expression representing Swag code.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SFct">#ast</span> <span class="SStr">"var x = 666"</span>
    <span class="SItr">@assert</span>(x == <span class="SNum">666</span>)
}

</span></div>
<h3 id="Returning_Source_from___ast_">Returning Source from <span class="code-inline">#ast</span></h3>
<p>A <span class="code-inline">#ast</span> block can include logic and must return a string to compile.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">var</span> cpt = <span class="SNum">2</span>
    <span class="SFct">#ast</span>
    {
        <span class="SKwd">const</span> <span class="SCst">INC</span> = <span class="SNum">5</span>
        <span class="SLgc">return</span> <span class="SStr">"cpt += "</span> ++ <span class="SCst">INC</span>
    }

    <span class="SItr">@assert</span>(cpt == <span class="SNum">7</span>)
}

</span></div>
<h3 id="Generating_Structs_and_Enums">Generating Structs and Enums</h3>
<p>You can use <span class="code-inline">#ast</span> inside struct or enum definitions to generate members dynamically.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">struct</span> <span class="SCst">MyStruct</span>
    {
        <span class="SFct">#ast</span>
        {
            <span class="SLgc">return</span> <span class="SStr">"x, y: s32 = 666"</span>
        }
    }

    <span class="SKwd">let</span> v: <span class="SCst">MyStruct</span>
    <span class="SItr">@assert</span>(v.x == <span class="SNum">666</span>)
    <span class="SItr">@assert</span>(v.y == <span class="SNum">666</span>)
}

</span></div>
<h3 id="Generating_Generic_Code">Generating Generic Code</h3>
<p><span class="code-inline">#ast</span> works with generics for flexible and reusable code generation.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SKwd">struct</span>(<span class="SCst">T</span>) <span class="SCst">MyStruct</span>
    {
        <span class="SFct">#ast</span>
        {
            <span class="SLgc">return</span> <span class="SStr">"x, y: "</span> ++ <span class="SItr">#typeof</span>(<span class="SCst">T</span>).name
        }

        z: <span class="SItr">#null</span> <span class="STpe">string</span>
    }

    <span class="SKwd">let</span> v: <span class="SFct">MyStruct</span>'<span class="STpe">bool</span>
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(v.x) == <span class="STpe">bool</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(v.y) == <span class="STpe">bool</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(v.z) == <span class="SItr">#null</span> <span class="STpe">string</span>)

    <span class="SKwd">let</span> v1: <span class="SFct">MyStruct</span>'<span class="STpe">f64</span>
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(v1.x) == <span class="STpe">f64</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(v1.y) == <span class="STpe">f64</span>)
    <span class="SCmp">#assert</span>(<span class="SItr">#typeof</span>(v1.z) == <span class="SItr">#null</span> <span class="STpe">string</span>)
}

</span></div>
<h3 id="Constructing_Strings_in___ast_">Constructing Strings in <span class="code-inline">#ast</span></h3>
<p><span class="code-inline">#ast</span> must return a string. You can construct it dynamically, e.g. by using a buffer.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#test</span>
{
    <span class="SAtr">#[Swag.Compiler]</span>
    <span class="SKwd">func</span> <span class="SFct">append</span>(buf: [*] <span class="STpe">u8</span>, start: <span class="STpe">s32</span>, val: <span class="STpe">string</span>)-&gt;<span class="STpe">s32</span>
    {
        <span class="SItr">@memcpy</span>(buf + start, <span class="SItr">@dataof</span>(val), <span class="SKwd">cast</span>(<span class="STpe">u64</span>) <span class="SItr">@countof</span>(val))
        <span class="SLgc">return</span> start + <span class="SKwd">cast</span>(<span class="STpe">s32</span>) <span class="SItr">@countof</span>(val)
    }

    <span class="SKwd">struct</span> <span class="SCst">Vector3</span>
    {
        <span class="SFct">#ast</span>
        {
            <span class="SKwd">var</span> buf: [<span class="SNum">256</span>] <span class="STpe">u8</span>
            <span class="SKwd">var</span> len = <span class="SNum">0</span>
            len = <span class="SFct">append</span>(buf, len, <span class="SStr">"x: f32 = 1\n"</span>)
            len = <span class="SFct">append</span>(buf, len, <span class="SStr">"y: f32 = 2\n"</span>)
            len = <span class="SFct">append</span>(buf, len, <span class="SStr">"z: f32 = 3\n"</span>)
            <span class="SLgc">return</span> <span class="SKwd">cast</span>(<span class="STpe">string</span>) <span class="SItr">@mkslice</span>(&amp;buf[<span class="SNum">0</span>], <span class="SKwd">cast</span>(<span class="STpe">u64</span>) len)
        }
    }

    <span class="SKwd">let</span> v: <span class="SCst">Vector3</span>
    <span class="SItr">@assert</span>(v.x == <span class="SNum">1</span>)
    <span class="SItr">@assert</span>(v.y == <span class="SNum">2</span>)
    <span class="SItr">@assert</span>(v.z == <span class="SNum">3</span>)
}

</span></div>
<h3 id="Real-World_Example">Real-World Example</h3>
<p>Example from Std.Core — dynamically generates a struct with all fields of another struct replaced by bools.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">struct</span>(<span class="SCst">T</span>) <span class="SCst">IsSet</span>
{
    <span class="SFct">#ast</span>
    {
        <span class="SKwd">var</span> str = <span class="SCst">StrConv</span>.<span class="SCst">StringBuilder</span>{}
        <span class="SKwd">let</span> typeof = <span class="SItr">#typeof</span>(<span class="SCst">T</span>)
        <span class="SLgc">for</span> f <span class="SLgc">in</span> typeof.fields:
            str.<span class="SFct">appendFormat</span>(<span class="SStr">"%: bool\n"</span>, f.name)
        <span class="SLgc">return</span> str.<span class="SFct">toString</span>()
    }
}
</span></div>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="__ast__at_Global_Scope"><span class="code-inline">#ast</span> at Global Scope</h3>
<p><span class="code-inline">#ast</span> can generate global declarations dynamically as well.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#ast</span>
{
    <span class="SKwd">const</span> value = <span class="SNum">666</span>
    <span class="SLgc">return</span> <span class="SStr">"const myGeneratedConst = "</span> ++ value
}

<span class="SCmp">#assert</span>(myGeneratedConst == <span class="SNum">666</span>)

</span></div>
<h3 id="_015_004_compiler_interface_swg">Compiler Interface</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>
</span></div>
<h3 id="The_Compiler_Interface">The Compiler Interface</h3>
<p><span class="code-inline">@compiler</span> exposes <span class="code-inline">Swag.ICompiler</span> while code is executing at compile time. At runtime the intrinsic is <span class="code-inline">null</span>, so keep it inside <span class="code-inline">#run</span>, <span class="code-inline">#message</span>, macros, mixins, or other compile-time-only code.</p>
<p>The current interface has three methods:</p>
<table class="table-markdown">
<tr><th>Method</th><th>Valid context</th><th>Result</th></tr>
<tr><td><span class="code-inline">getBuildCfg()</span></td><td>Compile-time code</td><td>Mutable configuration for the current module</td></tr>
<tr><td><span class="code-inline">getMessage()</span></td><td>A <span class="code-inline">#message</span> handler</td><td>Payload for the event being handled</td></tr>
<tr><td><span class="code-inline">compileString(source)</span></td><td>Compile-time code</td><td>Parse and add generated source to the module</td></tr>
</table>
<h3 id="Reading_the_Build_Configuration">Reading the Build Configuration</h3>
<p>A module setup file commonly uses <span class="code-inline">#run</span> to configure its build:</p>
<div class="code-block"><span class="SCde"><span class="SFct">#run</span>
{
    <span class="SKwd">let</span> cfg = <span class="SKwd">notnull</span> <span class="SItr">@compiler</span>.<span class="SFct">getBuildCfg</span>()
    cfg.moduleVersion  = <span class="SNum">1</span>
    cfg.moduleRevision = <span class="SNum">0</span>
    cfg.backendKind    = .<span class="SCst">Executable</span>
}
</span></div>
<p>Command-line options are resolved before this setup executes. The effective configuration is also available for inspection, but changing target paths or backend settings after compilation has started is not a supported way to override CLI options.</p>
<h3 id="Receiving_Compiler_Messages">Receiving Compiler Messages</h3>
<p>Subscribe with a mask from <span class="code-inline">Swag.CompilerMsgMask</span>:</p>
<div class="code-block"><span class="SCde"><span class="SFct">#message</span>(<span class="SCst">Swag</span>.<span class="SCst">CompilerMsgMask</span>.<span class="SCst">SemFunctions</span>)
{
    <span class="SKwd">let</span> message = <span class="SKwd">notnull</span> <span class="SItr">@compiler</span>.<span class="SFct">getMessage</span>()
    <span class="SLgc">if</span> message.type == <span class="SKwd">null</span> <span class="SLgc">or</span> message.name == <span class="SKwd">null</span> <span class="SLgc">do</span>
        <span class="SLgc">return</span>

    <span class="SKwd">let</span> functionType = <span class="SKwd">cast</span>(<span class="SKwd">const</span> *<span class="SCst">Swag</span>.<span class="SCst">TypeInfoFunc</span>) message.type
    <span class="SCmt">// Inspect functionType.parameters, functionType.returnType, and attributes.</span>
}
</span></div>
<p>The payload fields are nullable because their meaning depends on the event. Check <span class="code-inline">message.kind</span> and the fields you need before casting.</p>
<h3 id="Compiling_Generated_Source">Compiling Generated Source</h3>
<p><span class="code-inline">compileString</span> adds source to the same module. Generated code follows normal visibility rules; an injected file cannot name a symbol declared <span class="code-inline">private</span> in a different source file.</p>
<div class="code-block"><span class="SCde"><span class="SFct">#message</span>(<span class="SCst">Swag</span>.<span class="SCst">CompilerMsgMask</span>.<span class="SCst">PassAfterSemantic</span>)
{
    <span class="SItr">@compiler</span>.<span class="SFct">compileString</span>(
        <span class="SStr">"internal func generatedAnswer()-&gt;s32 { return 42 }\n"</span>)
}
</span></div>
<p>Prefer <span class="code-inline">#ast</span> when an expression or a small declaration can be generated locally. Use <span class="code-inline">compileString</span> for module-wide generation driven by compiler events. Keep generated names deterministic and include a final newline so diagnostic locations remain readable.</p>
<p>The runnable code-inspection section demonstrates a complete handler whose generated <span class="code-inline">#init</span> block is exercised by a test.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h2 id="_016_000_interoperability_swg">Interoperability</h2>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>
</span></div>
<p>Swag interoperates with native libraries through the target C ABI. Keep the boundary explicit: match the external declaration exactly, use fixed-width types, model nullability, and keep ownership rules in a small wrapper that presents ordinary Swag types to the rest of the program.</p>
<p>The current native toolchain targets Windows x86-64. The examples in this chapter therefore use Windows system libraries while keeping the ABI guidance portable.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_016_001_foreign_functions_swg">Foreign Functions</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Foreign_Functions">Foreign Functions</h3>
<p><span class="code-inline">#[Swag.Foreign]</span> declares a function implemented outside the Swag module. Its parameters are:</p>
<table class="table-markdown">
<tr><th>Parameter</th><th>Meaning</th></tr>
<tr><td><span class="code-inline">module</span></td><td>Dynamic module used to resolve the symbol</td></tr>
<tr><td><span class="code-inline">function</span></td><td>External symbol name; defaults to the Swag declaration name</td></tr>
<tr><td><span class="code-inline">link</span></td><td>Native import-library name when it differs from <span class="code-inline">module</span></td></tr>
<tr><td><span class="code-inline">callconv</span></td><td>ABI: <span class="code-inline">.C</span> by default, <span class="code-inline">.WindowsX64</span>, or <span class="code-inline">.Swag</span></td></tr>
</table>
<p><span class="code-inline">#foreignlib</span> registers the corresponding import library with the native linker. It does not declare functions by itself.</p>
<div class="code-block"><span class="SCde">
<span class="SCmp">#foreignlib</span>(<span class="SStr">"kernel32"</span>)

<span class="SAtr">#[Swag.Foreign(module: "kernel32")]</span>
{
    <span class="SKwd">func</span> <span class="SFct">GetCurrentProcessId</span>()-&gt;<span class="STpe">u32</span>
    <span class="SKwd">func</span> <span class="SFct">Sleep</span>(milliseconds: <span class="STpe">u32</span>)
}

<span class="SFct">#test</span>
{
    <span class="SItr">@assert</span>(<span class="SFct">GetCurrentProcessId</span>() != <span class="SNum">0</span>)
    <span class="SFct">Sleep</span>(<span class="SNum">0</span>)
}

</span></div>
<h3 id="Renamed_Symbols_and_Separate_Link_Names">Renamed Symbols and Separate Link Names</h3>
<p>Use <span class="code-inline">function</span> when the local name should differ from the exported symbol. Use <span class="code-inline">link</span> when runtime resolution and native linking use different library names:</p>
<div class="code-block"><span class="SCde"><span class="SAtr">#[Swag.Foreign(
    module: "vendor_runtime",
    function: "vendor_open_v2",
    link: "vendor_import",
    callconv: .C)]</span>
<span class="SKwd">func</span> <span class="SFct">openVendorHandle</span>(flags: <span class="STpe">u32</span>)-&gt;<span class="SItr">#null</span> *<span class="STpe">void</span>
</span></div>
<p>The declaration is an ABI contract, not a conversion layer. A mismatched parameter type, struct layout, calling convention, or nullability annotation can corrupt memory even when the code compiles.</p>
<div class="code-block"><span class="SCde">
</span></div>
<h3 id="_016_002_c_abi_data_swg">C Abi Data</h3>
<div class="code-block"><span class="SCde"><span class="SCmp">#global</span> <span class="SKwd">private</span>

</span></div>
<h3 id="Data_at_a_C_ABI_Boundary">Data at a C ABI Boundary</h3>
<p><span class="code-inline">cstring</span> represents a zero-terminated byte string. Swag's ordinary <span class="code-inline">string</span> stores an explicit byte count and may contain embedded zeroes, so crossing the ABI boundary should be an intentional conversion. String-literal storage has a trailing zero; take its data pointer before casting that pointer to <span class="code-inline">cstring</span>.</p>
<div class="code-block"><span class="SCde">
<span class="SFct">#test</span>
{
    <span class="SKwd">let</span> literal = <span class="SStr">"Swag"</span>
    <span class="SKwd">let</span> text    = <span class="SKwd">cast</span>(<span class="SKwd">const</span> <span class="STpe">cstring</span>) <span class="SItr">@dataof</span>(literal)
    <span class="SItr">@assert</span>(<span class="SItr">@countof</span>(text) == <span class="SNum">4</span>)
    <span class="SItr">@assert</span>(text[<span class="SNum">0</span>] == '<span class="SFct">S</span>'<span class="STpe">u8</span>)
    <span class="SItr">@assert</span>(text[<span class="SNum">3</span>] == '<span class="SFct">g</span>'<span class="STpe">u8</span>)
}

</span></div>
<p>For other data:</p>
<ul>
<li>Prefer <span class="code-inline">s8</span> through <span class="code-inline">s64</span> and <span class="code-inline">u8</span> through <span class="code-inline">u64</span> over platform-dependent C</li>
</ul>
<p>spellings.</p>
<ul>
<li>Represent optional C pointers with '#null <i>T' or '#null const </i>T'.</li>
<li>Match aggregate packing and alignment with <span class="code-inline">#[Swag.Pack]</span> and</li>
</ul>
<p><span class="code-inline">#[Swag.Align]</span> only when the external ABI requires it.</p>
<ul>
<li>State who owns returned memory and which function releases it.</li>
<li>Treat a returned pointer as borrowed unless the external API explicitly</li>
</ul>
<p>transfers ownership.</p>
<p><span class="code-inline">cvarargs</span> and <span class="code-inline">@cvastart</span>/<span class="code-inline">@cvaarg</span>/<span class="code-inline">@cvaend</span> exist for implementing or forwarding C-style variadic boundaries. Prefer a typed Swag wrapper: C default argument promotions and format-string contracts are not checked by the foreign declaration.</p>
<div class="code-block"><span class="SCde">
</span></div>
<div class="swag-watermark">Generated with <a href="https://swag-lang.org/index.php">swc</a> 0.1.1</div>
</div></div>
</div>
<script>
function getOffsetTop(element,parent){let offsetTop=0;while(element&&element!=parent){offsetTop+=element.offsetTop;element=element.offsetParent}return offsetTop}
document.addEventListener("DOMContentLoaded",function(){let hash=window.location.hash;if(!hash)return;let parent=document.querySelector(".right");let target=parent?parent.querySelector(hash):null;if(target)parent.scrollTop=getOffsetTop(target,parent)});
</script>
</body>
</html>
