# Swag Scope XML Viewer Backlog

This backlog covers the planned namespace-aware XML viewer and its synchronized source
and structural views.

### app.scope.xml.001 — XML has no namespace-aware structural reader

- Evidence: XML, project files, manifests, and XML logs open as colored code; SVG files go to the
  Image viewer, which offers no source view. Elements, attributes, namespaces, text nodes,
  comments, CDATA, processing instructions, and entity damage cannot be explored as a tree or
  addressed by a stable path.
- Next: build a bounded token/range index and synchronized source/tree view with namespace-aware
  paths, without resolving external entities or fetching schemas.
- Done when: every node retains its exact source range and qualified name, tree and source
  selection synchronize, namespaces and entity policy are inspectable, XPath-like navigation is
  local and bounded, malformed documents publish safe partial structure, and external resource
  access remains disabled.
