#version 330 core
#include base

out vec4 vcolor;
out vec2 vuv0;
out vec2 vpaintPos;

void main()
{
    gl_Position = mvp * mdl * vec4(vertexPosition, 0, 1);
    vcolor = vertexColor.zyxw;
    vuv0 = computeUVs(vertexPosition.xy);
    vpaintPos = vertexPosition.xy;
}
