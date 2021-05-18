const u = @import( "util.zig" );
const Interval1 = u.Interval1;
const Interval2 = u.Interval2;
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

pub fn setGLAttr( attr: c_int, value: c_int ) Error!void {
    return checkStatus( SDL_GL_SetAttribute( @intToEnum( SDL_GLattr, attr ), value ) );
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
    return @intToEnum( SDL_bool, if ( b ) SDL_TRUE else SDL_FALSE );
}

pub const Viewport = struct {
    x_PX: c_int,
    y_PX: c_int,
    w_PX: c_int,
    h_PX: c_int,

    pub fn asInterval_PX( self: *const Viewport ) Interval2 {
        return Interval2 {
            .x = Interval1.create( @intToFloat( f64, self.x_PX ), @intToFloat( f64, self.w_PX ) ),
            .y = Interval1.create( @intToFloat( f64, self.y_PX ), @intToFloat( f64, self.h_PX ) ),
        };
    }
};

pub fn getViewport( window: *SDL_Window ) Viewport {
    var viewport = Viewport { .x_PX = 0, .y_PX = 0, .w_PX = 0, .h_PX = 0 };
    SDL_GL_GetDrawableSize( window, &viewport.w_PX, &viewport.h_PX );
    return viewport;
}
