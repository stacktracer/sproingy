const std = @import( "std" );
pub usingnamespace @import( "c.zig" );
pub usingnamespace @import( "misc.zig" );

pub const GlzError = error {
    GenericFailure,
};

pub fn glzCreateProgram( vertSource: [*:0]const u8, fragSource: [*:0]const u8 ) !GLuint {
    const vertShader = try glzCompileShaderSource( GL_VERTEX_SHADER, vertSource );
    defer glDeleteShader( vertShader );

    const fragShader = try glzCompileShaderSource( GL_FRAGMENT_SHADER, fragSource );
    defer glDeleteShader( fragShader );

    const program = glCreateProgram( );

    glAttachShader( program, vertShader );
    defer glDetachShader( program, vertShader );

    glAttachShader( program, fragShader );
    defer glDetachShader( program, fragShader );

    glLinkProgram( program );

    var linkStatus: GLint = 0;
    glGetProgramiv( program, GL_LINK_STATUS, &linkStatus );
    if ( linkStatus != GL_TRUE ) {
        var messageSize: GLint = undefined;
        glGetProgramiv( program, GL_INFO_LOG_LENGTH, &messageSize );
        const allocator = std.heap.c_allocator;
        const message = try allocator.alloc( u8, @intCast( usize, messageSize ) );
        defer allocator.free( message );
        glGetProgramInfoLog( program, messageSize, null, message.ptr );
        std.debug.warn( "Shader linking failed:\n{s}\n", .{ message } );
        // TODO: Make message available to caller
        return GlzError.GenericFailure;
    }

    return program;
}

pub fn glzCompileShaderSource( shaderType: GLenum, source: [*:0]const u8 ) !GLuint {
    const shader = glCreateShader( shaderType );
    glShaderSource( shader, 1, &source, null );
    glCompileShader( shader );

    var compileStatus: GLint = 0;
    glGetShaderiv( shader, GL_COMPILE_STATUS, &compileStatus );
    if ( compileStatus != GL_TRUE ) {
        var messageSize: GLint = undefined;
        glGetShaderiv( shader, GL_INFO_LOG_LENGTH, &messageSize );
        const allocator = std.heap.c_allocator;
        const message = try allocator.alloc( u8, @intCast( usize, messageSize ) );
        defer allocator.free( message );
        glGetShaderInfoLog( shader, messageSize, null, message.ptr );
        std.debug.warn( "Shader compilation failed:\n{s}\n", .{ message } );
        // TODO: Make message available to caller
        return GlzError.GenericFailure;
    }

    return shader;
}

pub fn glzEnablePremultipliedAlphaBlending( ) void {
    glBlendEquation( GL_FUNC_ADD );
    glBlendFunc( GL_ONE, GL_ONE_MINUS_SRC_ALPHA );
    glEnable( GL_BLEND );
}

pub fn glzDisableBlending( ) void {
    glDisable( GL_BLEND );
}

pub fn glzUniformInterval2( location: GLint, interval: Interval2 ) void {
    glUniform4f( location,
                 @floatCast( f32, interval.x.min ),
                 @floatCast( f32, interval.y.min ),
                 @floatCast( f32, interval.x.span ),
                 @floatCast( f32, interval.y.span ) );
}

pub fn glzGetViewport_PX( ) Interval2 {
    var viewport_PX: [4]GLint = [_]GLint{ -1, -1, -1, -1 };
    glGetIntegerv( GL_VIEWPORT, &viewport_PX );
    return xywh( @intToFloat( f64, viewport_PX[0] ), @intToFloat( f64, viewport_PX[1] ), @intToFloat( f64, viewport_PX[2] ), @intToFloat( f64, viewport_PX[3] ) );
}

pub fn glzWheelSteps( ev: *GdkEventScroll ) f64 {
    var direction: GdkScrollDirection = undefined;
    if ( gdk_event_get_scroll_direction( @ptrCast( *GdkEvent, ev ), &direction ) != 0 ) {
        return switch ( direction ) {
            .GDK_SCROLL_UP => 1.0,
            .GDK_SCROLL_DOWN => -1.0,
            else => 0.0,
        };
    }

    var xDelta: f64 = undefined;
    var yDelta: f64 = undefined;
    if ( gdk_event_get_scroll_deltas( @ptrCast( *GdkEvent, ev ), &xDelta, &yDelta ) != 0 ) {
        return yDelta;
    }

    return 0.0;
}

pub fn glzHasCurrentContext( ) bool {
    var major: GLint = -1;
    glGetIntegerv( GL_MAJOR_VERSION, &major );
    return ( major != -1 );
}
