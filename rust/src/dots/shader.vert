#version 150 core

vec2 min2D( vec4 interval2D ) {
    return interval2D.xy;
}

vec2 span2D( vec4 interval2D ) {
    return interval2D.zw;
}

vec2 coordsToNdc2D( vec2 coords, vec4 bounds ) {
    vec2 frac = ( coords - min2D( bounds ) ) / span2D( bounds );
    return ( -1.0 + 2.0*frac );
}

uniform vec4 XY_BOUNDS;
uniform float SIZE_PX;

// x_XAXIS, y_YAXIS
in vec2 inCoords;

void main( void ) {
    vec2 xy_XYAXIS = inCoords.xy;
    gl_Position = vec4( coordsToNdc2D( xy_XYAXIS, XY_BOUNDS ), 0.0, 1.0 );
    gl_PointSize = SIZE_PX;
}
