#version 150 core
precision lowp float;

const float FEATHER_PX = 0.9;

uniform float SIZE_PX;
uniform vec4 RGBA;

out vec4 outRgba;

void main( void ) {
    vec2 xy_NPC = -1.0 + 2.0*gl_PointCoord;
    float r_NPC = sqrt( dot( xy_NPC, xy_NPC ) );

    float pxToNpc = 2.0 / SIZE_PX;
    float rOuter_NPC = 1.0 - 0.5*pxToNpc;
    float rInner_NPC = rOuter_NPC - FEATHER_PX*pxToNpc;
    float mask = smoothstep( rOuter_NPC, rInner_NPC, r_NPC );

    float alpha = mask * RGBA.a;
    outRgba = vec4( alpha*RGBA.rgb, alpha );
}
