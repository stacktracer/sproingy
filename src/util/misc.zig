const std = @import( "std" );
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const Vec2 = struct {
    x: f64,
    y: f64,

    pub fn init( x: f64, y: f64 ) Vec2 {
        return Vec2 {
            .x = x,
            .y = y,
        };
    }

    pub fn set( self: *Vec2, x: f64, y: f64 ) void {
        self.x = x;
        self.y = y;
    }
};

pub fn xy( x: f64, y: f64 ) Vec2 {
    return Vec2.init( x, y );
}

pub const Interval1 = struct {
    /// Inclusive lower bound.
    min: f64,

    /// Difference between min and exclusive upper bound.
    span: f64,

    pub fn init( min: f64, span: f64 ) Interval1 {
        return Interval1 {
            .min = min,
            .span = span,
        };
    }

    pub fn initMinMax( min: f64, max: f64 ) Interval1 {
        return Interval1.init( min, max - min );
    }

    pub fn set( self: *Interval1, min: f64, span: f64 ) void {
        self.min = min;
        self.span = span;
    }

    pub fn valueToFrac( self: *const Interval1, value: f64 ) f64 {
        return ( ( value - self.min ) / self.span );
    }

    pub fn fracToValue( self: *const Interval1, frac: f64 ) f64 {
        return ( self.min + frac*self.span );
    }
};

pub const Interval2 = struct {
    x: Interval1,
    y: Interval1,

    pub fn init( x: f64, y: f64, w: f64, h: f64 ) Interval2 {
        return Interval2 {
            .x = Interval1.init( x, w ),
            .y = Interval1.init( y, h ),
        };
    }

    pub fn valueToFrac( self: *const Interval2, value: Vec2 ) Vec2 {
        return Vec2 {
            .x = self.x.valueToFrac( value.x ),
            .y = self.y.valueToFrac( value.y ),
        };
    }

    pub fn fracToValue( self: *const Interval2, frac: Vec2 ) Vec2 {
        return Vec2 {
            .x = self.x.fracToValue( frac.x ),
            .y = self.y.fracToValue( frac.y ),
        };
    }
};

pub fn xywh( x: f64, y: f64, w: f64, h: f64 ) Interval2 {
    return Interval2.init( x, y, w, h );
}

pub const ProcessArgs = struct {
    allocator: *Allocator,
    args: ArrayList( [:0]u8 ),
    argsAsCstrs: ArrayList( [*c]u8 ),
    argc: c_int,
    argv: [*c][*c]u8,

    pub fn init( allocator: *Allocator ) !ProcessArgs {
        var it = std.process.args( );
        defer it.deinit( );

        var args = ArrayList( [:0]u8 ).init( allocator );
        var argsAsCstrs = ArrayList( [*c]u8 ).init( allocator );
        while ( true ) {
            const arg = try ( it.next( allocator ) orelse break );
            try args.append( arg );
            try argsAsCstrs.append( arg.ptr );
        }

        return ProcessArgs {
            .allocator = allocator,
            .args = args,
            .argsAsCstrs = argsAsCstrs,
            .argc = @intCast( c_int, argsAsCstrs.items.len ),
            .argv = argsAsCstrs.items.ptr,
        };
    }

    pub fn deinit( self: *ProcessArgs ) void {
        self.argc = 0;
        self.argv = null;

        // Don't free ptrs in self.argsAsCstrs -- they point to the same memory as slices in self.args
        self.argsAsCstrs.deinit( );

        for ( self.args.items ) |arg| {
            self.allocator.free( arg );
        }
        self.args.deinit( );
    }
};
