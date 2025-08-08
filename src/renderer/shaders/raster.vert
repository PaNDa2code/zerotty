#version 450 core

layout(location = 0) in uvec2 point;
layout(location = 1) in uint tag;
layout(location = 2) in uint contoure;

layout(location = 3) in uvec2 rect_start;
layout(location = 4) in uvec2 rect_size;

layout(location = 5) in uvec2 bbox_min;
layout(location = 6) in uvec2 bbox_max;

void main() {}
