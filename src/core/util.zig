pub const Bound = struct {
    coord: f64,
    inclusive: bool,

    pub fn init( coord: f64, inclusive: bool ) Bound {
        return Bound {
            .coord = coord,
            .inclusive = inclusive,
        };
    }
};

pub const Interval = struct {
    /// Inclusive start point.
    start: f64,

    /// Difference between start and exclusive end.
    span: f64,

    pub fn init( start: f64, span: f64 ) Interval {
        return Interval {
            .start = start,
            .span = span,
        };
    }

    pub fn initStartEnd( start: f64, end_: f64 ) Interval {
        return init( start, end_ - start );
    }

    pub fn set( self: *Interval, start: f64, span: f64 ) void {
        self.start = start;
        self.span = span;
    }

    pub fn valueToFrac( self: *const Interval, value: f64 ) f64 {
        return ( ( value - self.start ) / self.span );
    }

    pub fn fracToValue( self: *const Interval, frac: f64 ) f64 {
        return ( self.start + frac*self.span );
    }

    /// Exclusive.
    pub fn end( self: *const Interval ) f64 {
        return ( self.start + self.span );
    }

    pub fn lowerBound( self: *const Interval ) Bound {
        if ( self.span >= 0 ) {
            return Bound.init( self.start, true );
        }
        else {
            return Bound.init( self.end( ), false );
        }
    }

    pub fn upperBound( self: *const Interval ) Bound {
        if ( self.span >= 0 ) {
            return Bound.init( self.end( ), false );
        }
        else {
            return Bound.init( self.start, true );
        }
    }
};
