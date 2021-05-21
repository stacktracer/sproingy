pub const Vec2 = struct {
    x: f64,
    y: f64,

    pub fn set( self: *Vec2, x: f64, y: f64 ) void {
        self.x = x;
        self.y = y;
    }
};

pub fn xy( x: f64, y: f64 ) Vec2 {
    return Vec2 {
        .x = x,
        .y = y,
    };
}

pub const Interval1 = struct {
    /// Inclusive lower bound.
    min: f64,

    /// Difference between min and exclusive upper bound.
    span: f64,

    pub fn create( min: f64, span: f64 ) Interval1 {
        return Interval1 {
            .min = min,
            .span = span,
        };
    }

    pub fn createWithMinMax( min: f64, max: f64 ) Interval1 {
        return Interval1.create( min, max - min );
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
    return Interval2 {
        .x = Interval1.create( x, w ),
        .y = Interval1.create( y, h ),
    };
}
