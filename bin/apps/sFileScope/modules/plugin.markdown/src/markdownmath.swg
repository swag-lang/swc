using Core

// Renders the most common TeX notation as readable Unicode while keeping unknown commands visible.
// The document viewer is offline and intentionally does not execute a browser-side math engine.
func renderMarkdownMath(source: string)->String
{
    var result = String.from(Latin1.trim(source))
    for replacement in [{"\\alpha", "α"}, {"\\beta", "β"}, {"\\gamma", "γ"}, {"\\delta", "δ"}, {"\\epsilon", "ε"}, {"\\theta", "θ"}, {"\\lambda", "λ"}, {"\\mu", "μ"}, {"\\pi", "π"}, {"\\rho", "ρ"}, {"\\sigma", "σ"}, {"\\tau", "τ"}, {"\\phi", "φ"}, {"\\omega", "ω"}, {"\\Gamma", "Γ"}, {"\\Delta", "Δ"}, {"\\Theta", "Θ"}, {"\\Lambda", "Λ"}, {"\\Pi", "Π"}, {"\\Sigma", "Σ"}, {"\\Phi", "Φ"}, {"\\Omega", "Ω"}, {"\\times", "×"}, {"\\cdot", "·"}, {"\\pm", "±"}, {"\\leq", "≤"}, {"\\geq", "≥"}, {"\\neq", "≠"}, {"\\approx", "≈"}, {"\\infty", "∞"}, {"\\sum", "∑"}, {"\\prod", "∏"}, {"\\int", "∫"}, {"\\partial", "∂"}, {"\\nabla", "∇"}, {"\\rightarrow", "→"}, {"\\leftarrow", "←"}, {"\\Rightarrow", "⇒"}, {"\\Leftarrow", "⇐"}, {"\\in", "∈"}, {"\\notin", "∉"}, {"\\subset", "⊂"}, {"\\subseteq", "⊆"}, {"\\cup", "∪"}, {"\\cap", "∩"}]
    {
        result.replace(replacement.item0, replacement.item1)
    }

    result.replace("\\,", " ")
    result.replace("\\;", " ")
    result.replace("\\quad", "  ")
    result.replace("\\left", "")
    result.replace("\\right", "")
    result.replace("^0", "⁰")
    result.replace("^1", "¹")
    result.replace("^2", "²")
    result.replace("^3", "³")
    result.replace("^n", "ⁿ")
    result.replace("_0", "₀")
    result.replace("_1", "₁")
    result.replace("_2", "₂")
    result.replace("_3", "₃")
    result.replace("{", "")
    result.replace("}", "")
    return result
}
