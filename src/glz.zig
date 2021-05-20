const std = @import( "std" );
const u = @import( "util.zig" );
const Interval2 = u.Interval2;
const cAllocator = std.heap.c_allocator;
usingnamespace @cImport( {
    @cInclude( "epoxy/gl.h" );
} );

const GlzError = error {
    GenericFailure,
};

// TODO: Maybe take an allocator arg, but only if we're going to have an allocator handy for other purposes
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
        const message = try cAllocator.alloc( u8, @intCast( usize, messageSize ) );
        defer cAllocator.free( message );
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
        const message = try cAllocator.alloc( u8, @intCast( usize, messageSize ) );
        defer cAllocator.free( message );
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

pub fn glzdisableBlending( ) void {
    glDisable( GL_BLEND );
}

pub fn glzUniformInterval2( location: GLint, interval: Interval2 ) void {
    glUniform4f( location,
                 @floatCast( f32, interval.x.min ),
                 @floatCast( f32, interval.y.min ),
                 @floatCast( f32, interval.x.span ),
                 @floatCast( f32, interval.y.span ) );
}
