const u = @import( "util.zig" );
const Interval2 = u.Interval2;
const xywh = u.xywh;
pub usingnamespace @cImport( {
    @cInclude( "SDL2/SDL.h" );
} );

const Error = error {
    GenericFailure,
};

pub fn checkStatus( status: c_int ) !void {
    if ( status != 0 ) {
        return Error.GenericFailure;
    }
}

pub fn initSDL( flags: u32 ) !void {
    if ( SDL_Init( SDL_INIT_VIDEO ) != 0 ) {
        return Error.GenericFailure;
    }
}

pub fn createWindow( title: [*]const u8, x: c_int, y: c_int, w: c_int, h: c_int, flags: u32 ) !*SDL_Window {
    return SDL_CreateWindow( title, x, y, w, h, flags ) orelse Error.GenericFailure;
}

pub fn getWindowID( window: *SDL_Window ) !u32 {
    const result = SDL_GetWindowID( window );
    return ( if ( result != 0 ) result else Error.GenericFailure );
}

pub fn setGLAttr( attr: SDL_GLattr, value: c_int ) Error!void {
    return checkStatus( SDL_GL_SetAttribute( attr, value ) );
}

pub fn createGLContext( window: *SDL_Window ) !*SDL_GLContext {
    return SDL_GL_CreateContext( window ) orelse Error.GenericFailure;
}

pub fn makeGLCurrent( window: *SDL_Window, context: SDL_GLContext ) !void {
    return checkStatus( SDL_GL_MakeCurrent( window, context ) );
}

pub fn setGLSwapInterval( interval: c_int ) !void {
    return checkStatus( SDL_GL_SetSwapInterval( interval ) );
}

pub fn setMouseConfinedToWindow( window: *SDL_Window, confined: bool ) void {
    SDL_SetWindowGrab( window, fromBool( confined ) );
}

pub fn fromBool( b: bool ) SDL_bool {
    return if ( b ) .SDL_TRUE else .SDL_FALSE;
}

pub const FrameSize = struct {
    /// Size in logical pixels (aka screen coordinates)
    w_LPX: c_int,

    /// Height in logical pixels (aka screen coordinates)
    h_LPX: c_int,

    /// Width in physical pixels
    w_PX: c_int,

    /// Height in physical pixels
    h_PX: c_int,

    /// Device Pixel Ratio in horizontal direction
    xDpr: f64,

    /// Device Pixel Ratio in vertical direction
    yDpr: f64,

    pub fn asViewport_PX( self: *const FrameSize ) Interval2 {
        return xywh( 0, 0, @intToFloat( f64, self.w_PX ), @intToFloat( f64, self.h_PX ) );
    }
};

pub fn getFrameSize( window: *SDL_Window ) FrameSize {
    var result: FrameSize = undefined;
    SDL_GetWindowSize( window, &result.w_LPX, &result.h_LPX );
    SDL_GL_GetDrawableSize( window, &result.w_PX, &result.h_PX );
    result.xDpr = @intToFloat( f64, result.w_PX ) / @intToFloat( f64, result.w_LPX );
    result.yDpr = @intToFloat( f64, result.h_PX ) / @intToFloat( f64, result.h_LPX );
    return result;
}
