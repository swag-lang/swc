# Swag Scope ODP Viewer Backlog

Reading and inspecting OpenDocument presentations.

### app.scope.odp.001 — ODP reading lacks full master and drawing fidelity

- Evidence: ODP fits common positioned text, rectangles and raster pictures with basic
  style/master inheritance. Speaker notes are available in a separate theme-aware prose
  reader. Group transforms and unsupported drawings fall back to text. Media, gradients,
  full master placeholder geometry and complex shapes are absent. Slides load eagerly.
- Next: deepen Impress master and shape fidelity, identify unsupported components, and
  defer off-screen slide work.
- Done when: representative LibreOffice Impress presentations retain common authored
  slide geometry and drawings, speaker notes remain separately inspectable, unsupported
  content is named, and navigation, cancellation and package budgets hold for large and
  damaged presentations.
