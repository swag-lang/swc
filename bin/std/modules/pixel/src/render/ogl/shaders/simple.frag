#version 330 core
#include base

in vec4 vcolor;
in vec2 vuv0;
in vec2 vpaintPos;

out vec4 color;

void main()
{
    color = vcolor * samplePaint(vpaintPos, vuv0);
}
