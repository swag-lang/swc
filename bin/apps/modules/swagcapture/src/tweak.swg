const MinBorderSize     = 1.0
const MaxBorderSize     = 100.0
const MinTextBorderSize = 1.0
const MaxTextBorderSize = 20.0
const MinCapSize        = 1.0
const MaxCapSize        = 8.0
const MinFontSize       = 10.0
const MaxFontSize       = 150.0
const MinBoldSize       = 0.0
const MaxBoldSize       = 20.0

// The same margin for a preset sample, which is drawn at a fraction of that size.
//
// Everything a sample paints outside its own rectangle is scaled down with it, so the
// document margin would size the layer of a 44 pixel picture at 438 pixels a side — a
// hundred times the pixels, on the one surface that repaints on every hover.
const QuickPaintOverdraw = 32.0

const ColorRed:    Color = 0xFFE80808
const ColorGreen:  Color = 0xFF60C447
const ColorBlue:   Color = 0xFF199CF4
const ColorYellow: Color = 0xFFFDDF1B
