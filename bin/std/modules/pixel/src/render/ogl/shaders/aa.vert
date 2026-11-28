#version 330 core
#include base

out vec4  vcolor;
out vec2  vuv0;
out vec2  vuv1;
out vec2  vpaintPos;
out float vcov;

void main()
{
    gl_Position = mvp * mdl * vec4(vertexPosition, 0, 1);

    // source is rgba, and we need bgra
    vcolor = vertexColor.zyxw;

    // uv
    vuv0 = computeUVs(vertexPosition.xy);
    vuv1.x = uv1.x;
    vuv1.y = 1 - uv1.y;
    vpaintPos = vertexPosition.xy;

    // antialiasing coverage (extruded-fringe). Linearly interpolated across the
    // 1px fringe band: 1 inside the shape, 0 on the outer fringe edge.
    vcov = aaCoverage;
}
