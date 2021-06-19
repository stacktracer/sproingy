const std = @import( "std" );
const min = std.math.min;
const maxInt = std.math.maxInt;
pub usingnamespace @import( "c.zig" );
usingnamespace @import( "util.zig" );

pub const GlzError = error {
    GenericFailure,
};

pub fn glzBufferData( target: GLenum, comptime T: type, values: []const T, usage: GLenum ) void {
    if ( values.len > 0 ) {
        const maxCount = @divTrunc( maxInt( GLsizeiptr ), @sizeOf( T ) );
        if ( values.len > maxCount ) {
            std.debug.warn( "Pushing fewer values than requested to device: requested = {d}, allowed = {d}\n", .{ values.len, maxCount } );
        }
        const actualCount = min( values.len, maxCount );
        const bytesCount = @intCast( GLsizeiptr, actualCount * @sizeOf( T ) );
        const bytesPtr = @ptrCast( *const c_void, values.ptr );
        glBufferData( target, bytesCount, bytesPtr, usage );
    }
    else {
        // FIXME: glBufferData with null?
    }
}

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

pub fn glzHasCurrentContext( ) bool {
    var major: GLint = -1;
    glGetIntegerv( GL_MAJOR_VERSION, &major );
    return ( major != -1 );
}

pub fn glzUniformInterval1( location: GLint, interval: Interval ) void {
    glUniform2f( location,
                 @floatCast( f32, interval.start ),
                 @floatCast( f32, interval.span ) );
}

pub fn glzUniformInterval2( location: GLint, interval: [2]Interval ) void {
    glUniform4f( location,
                 @floatCast( f32, interval[0].start ),
                 @floatCast( f32, interval[1].start ),
                 @floatCast( f32, interval[0].span ),
                 @floatCast( f32, interval[1].span ) );
}

pub fn glzGetViewport_PX( ) [2]Interval {
    var viewport_PX: [4]GLint = [_]GLint{ -1, -1, -1, -1 };
    glGetIntegerv( GL_VIEWPORT, &viewport_PX );
    const x = @intToFloat( f64, viewport_PX[0] );
    const y = @intToFloat( f64, viewport_PX[1] );
    const w = @intToFloat( f64, viewport_PX[2] );
    const h = @intToFloat( f64, viewport_PX[3] );
    return [_]Interval {
        Interval.init( x, w ),
        Interval.init( y, h ),
    };
}
