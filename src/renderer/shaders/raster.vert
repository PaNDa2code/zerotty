#version 450 core

layout(location = 0) in uvec2 point;
layout(location = 1) in uint tag;
layout(location = 2) in uint contoure;

layout(location = 3) in uvec2 rect_start;
layout(location = 4) in uvec2 rect_size;

layout(location = 5) in uvec2 bbox_min;
layout(location = 6) in uvec2 bbox_max;

#define BEZIER_CONTROL_POINT_BIT 0x01
#define BEZIER_THIRD_ORDER_BIT 0x02

#define IS_BEZIER_CONTROL_POINT(tag) (( tag & BEZIER_CONTROL_POINT_BIT ) != 0)
#define IS_BEZIER_THIRD_ORDER(tag) (( tag & BEZIER_THIRD_ORDER_BIT ) != 0)

void main() {
    if (IS_BEZIER_CONTROL_POINT(tag)) {
        // TODO
        if (IS_BEZIER_THIRD_ORDER(tag)) {
            // TODO
        }
    }
}
