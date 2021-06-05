const std = @import( "std" );
const sqrt = std.math.sqrt;
const minInt = std.math.minInt;
const milliTimestamp = std.time.milliTimestamp;

/// Impls must be thread-safe.
pub const SimControl = struct {
    setBoxFn: fn ( self: *SimControl, boxCoords: []const f64 ) anyerror!void,
    keepRunningFn: fn ( self: *SimControl ) bool,
    getUpdateIntervalFn_MILLIS: fn ( self: *SimControl ) i64,
    setDotsFn: fn ( self: *SimControl, dotCoords: []const f64 ) anyerror!void,

    pub fn setBox( self: *SimControl, boxCoords: []const f64 ) !void {
        return self.setBoxFn( self, boxCoords );
    }

    pub fn keepRunning( self: *SimControl ) bool {
        return self.keepRunningFn( self );
    }

    pub fn getUpdateInterval_MILLIS( self: *SimControl ) i64 {
        return self.getUpdateIntervalFn_MILLIS( self );
    }

    pub fn setDots( self: *SimControl, dotCoords: []const f64 ) !void {
        return self.setDotsFn( self, dotCoords );
    }
};

/// Caller must ensure that control exists until after this fn returns.
pub fn runSimulation( control: *SimControl ) void {
    // Coords per dot
    comptime const n = 2;

    // TODO: Move sim config to main

    const dotCount = 3;
    const coordCount = dotCount * n;
    const masses = [ dotCount ]f64 { 1.0, 1.0, 1.0 };
    const xsStart = [ coordCount ]f64 { -6.0,-3.0, -6.5,-3.0, -6.1,-3.2 };
    const vsStart = [ coordCount ]f64 { 7.0,13.0,  2.0,14.0,  5.0,6.0 };

    const xMins = [n]f64 { -8.0, -6.0 };
    const xMaxs = [n]f64 {  8.0,  6.0 };

    // Send box coords to the UI
    var boxCoords = [_]f64 { xMins[0],xMaxs[1], xMins[0],xMins[1], xMaxs[0],xMaxs[1], xMaxs[0],xMins[1] };
    control.setBox( &boxCoords ) catch @panic( "" );

    // Pre-compute the first coord index of each dot, for easy iteration later
    var dotFirstCoordIndices = [_]usize { undefined } ** dotCount; {
        var dotIndex = @as( usize, 0 );
        while ( dotIndex < dotCount ) : ( dotIndex += 1 ) {
            dotFirstCoordIndices[ dotIndex ] = dotIndex * n;
        }
    }

    // TODO: Use SIMD Vectors?
    // TODO: Multi-thread? (If so, avoid false sharing)

    const tFull = @as( f64, 500e-9 );
    const tHalf = 0.5*tFull;

    var coordArrays: [7][coordCount]f64 = undefined;
    var xsCurr = @as( []f64, &coordArrays[0] );
    var xsNext = @as( []f64, &coordArrays[1] );
    var vsCurr = @as( []f64, &coordArrays[2] );
    var vsHalf = @as( []f64, &coordArrays[3] );
    var vsNext = @as( []f64, &coordArrays[4] );
    var asCurr = @as( []f64, &coordArrays[5] );
    var asNext = @as( []f64, &coordArrays[6] );

    var gravity = ConstantAcceleration.init( [_]f64 { 0.0, -9.80665 } );
    var springs = SpringsAcceleration.init( 0.6, 300.0, &xsCurr );
    const accelerators = [_]*Accelerator { &gravity.accelerator, &springs.accelerator };

    xsCurr[ 0..coordCount ].* = xsStart;
    vsCurr[ 0..coordCount ].* = vsStart;
    for ( dotFirstCoordIndices ) |dotFirstCoordIndex,dotIndex| {
        const xCurr = xsCurr[ dotFirstCoordIndex.. ][ 0..n ];
        var aCurr = asCurr[ dotFirstCoordIndex.. ][ 0..n ];
        aCurr.* = [_]f64 { 0.0 } ** n;
        for ( accelerators ) |accelerator| {
            accelerator.addAcceleration( dotIndex, masses[ dotIndex ], xCurr.*, aCurr );
        }
    }

    // TODO: Exit condition?
    const updateInterval_MILLIS = control.getUpdateInterval_MILLIS( );
    var nextUpdate_PMILLIS = @as( i64, minInt( i64 ) );
    while ( control.keepRunning( ) ) {
        // Send dot coords to the listener periodically
        const now_PMILLIS = milliTimestamp( );
        if ( now_PMILLIS >= nextUpdate_PMILLIS ) {
            control.setDots( xsCurr ) catch @panic( "" );
            nextUpdate_PMILLIS = now_PMILLIS + updateInterval_MILLIS;
        }

        // Update dot coords, but without checking for bounces
        for ( vsCurr ) |vCurr,coordIndex| {
            vsHalf[ coordIndex ] = vCurr + asCurr[ coordIndex ]*tHalf;
        }
        for ( xsCurr ) |xCurr,coordIndex| {
            xsNext[ coordIndex ] = xCurr + vsHalf[ coordIndex ]*tFull;
        }
        for ( dotFirstCoordIndices ) |dotFirstCoordIndex,dotIndex| {
            var xNext = xsNext[ dotFirstCoordIndex.. ][ 0..n ];
            var aNext = asNext[ dotFirstCoordIndex.. ][ 0..n ];
            aNext.* = [_]f64 { 0.0 } ** n;
            for ( accelerators ) |accelerator| {
                accelerator.addAcceleration( dotIndex, masses[ dotIndex ], xNext.*, aNext );
            }
        }
        for ( vsHalf ) |vHalf,coordIndex| {
            vsNext[ coordIndex ] = vHalf + asNext[ coordIndex ]*tHalf;
        }

        // Handle bounces
        for ( dotFirstCoordIndices ) |dotFirstCoordIndex,dotIndex| {
            // TODO: Profile, speed up
            var xNext = xsNext[ dotFirstCoordIndex.. ][ 0..n ];

            // Bail immediately in the common case with no bounce
            var hasBounce = false;
            for ( xNext ) |xNext_i,i| {
                if ( xNext_i <= xMins[i] or xNext_i >= xMaxs[i] ) {
                    hasBounce = true;
                    break;
                }

                const aCurr_i = asCurr[ dotFirstCoordIndex + i ];
                const vCurr_i = vsCurr[ dotFirstCoordIndex + i ];
                const tTip_i = vCurr_i / ( -2.0 * aCurr_i );
                if ( 0 <= tTip_i and tTip_i < tFull ) {
                    const xCurr_i = xsCurr[ dotFirstCoordIndex + i ];
                    const xTip_i = xCurr_i + vCurr_i*tTip_i + 0.5*aCurr_i*tTip_i*tTip_i;
                    if ( xTip_i <= xMins[i] or xTip_i >= xMaxs[i] ) {
                        hasBounce = true;
                        break;
                    }
                }
            }
            if ( !hasBounce ) {
                continue;
            }

            const mass = masses[ dotIndex ];

            var aNext = asNext[ dotFirstCoordIndex.. ][ 0..n ];
            var vNext = vsNext[ dotFirstCoordIndex.. ][ 0..n ];
            var vHalf = vsHalf[ dotFirstCoordIndex.. ][ 0..n ];

            var aCurr = [_]f64 { undefined } ** n;
            var vCurr = [_]f64 { undefined } ** n;
            var xCurr = [_]f64 { undefined } ** n;
            aCurr = asCurr[ dotFirstCoordIndex.. ][ 0..n ].*;
            vCurr = vsCurr[ dotFirstCoordIndex.. ][ 0..n ].*;
            xCurr = xsCurr[ dotFirstCoordIndex.. ][ 0..n ].*;

            while ( true ) {
                // Time of soonest bounce, and what to multiply each velocity coord by at that time
                var tBounce = std.math.inf( f64 );
                var vBounceFactor = [_]f64 { 1.0 } ** n;
                for ( xNext ) |xNext_i,i| {
                    var hasMinBounce = false;
                    var hasMaxBounce = false;

                    if ( xNext_i <= xMins[i] ) {
                        hasMinBounce = true;
                    }
                    else if ( xNext_i >= xMaxs[i] ) {
                        hasMaxBounce = true;
                    }

                    const tTip_i = vCurr[i] / ( -2.0 * aCurr[i] );
                    if ( 0 <= tTip_i and tTip_i < tFull ) {
                        const xTip_i = xCurr[i] + vCurr[i]*tTip_i + 0.5*aCurr[i]*tTip_i*tTip_i;
                        if ( xTip_i <= xMins[i] ) {
                            hasMinBounce = true;
                        }
                        else if ( xTip_i >= xMaxs[i] ) {
                            hasMaxBounce = true;
                        }
                    }

                    var tsBounce_i_ = [_]f64{ undefined } ** 4;
                    var tsBounce_i = Buffer.init( &tsBounce_i_ );
                    if ( hasMinBounce ) {
                        appendBounceTimes( xCurr[i], vCurr[i], aCurr[i], xMins[i], &tsBounce_i );
                    }
                    if ( hasMaxBounce ) {
                        appendBounceTimes( xCurr[i], vCurr[i], aCurr[i], xMaxs[i], &tsBounce_i );
                    }
                    for ( tsBounce_i.items[ 0..tsBounce_i.size ] ) |tBounce_i| {
                        if ( 0 <= tBounce_i and tBounce_i < tFull ) {
                            if ( tBounce_i < tBounce ) {
                                tBounce = tBounce_i;
                                vBounceFactor = [_]f64 { 1.0 } ** n;
                                vBounceFactor[i] = -1.0;
                            }
                            else if ( tBounce_i == tBounce ) {
                                vBounceFactor[i] = -1.0;
                            }
                        }
                    }
                }

                // If soonest bounce is after timestep end, then bounce update is done
                if ( tBounce > tFull ) {
                    break;
                }

                // Update from 0 to tBounce
                {
                    var tFull_ = tBounce;
                    var tHalf_ = 0.5 * tFull_;
                    var aNext_ = [_]f64 { undefined } ** n;
                    var vNext_ = [_]f64 { undefined } ** n;
                    var xNext_ = [_]f64 { undefined } ** n;
                    for ( vCurr ) |vCurr_i,i| {
                        vHalf[i] = vCurr_i + aCurr[i]*tHalf_;
                    }
                    for ( xCurr ) |xCurr_i,i| {
                        xNext_[i] = xCurr_i + vHalf[i]*tFull_;
                    }
                    aNext_ = [_]f64 { 0.0 } ** n;
                    for ( accelerators ) |accelerator| {
                        accelerator.addAcceleration( dotIndex, mass, xNext_, &aNext_ );
                    }
                    for ( vHalf ) |vHalf_i,i| {
                        vNext_[i] = vHalf_i + aNext_[i]*tHalf_;
                    }

                    aCurr = aNext_;
                    for ( vNext_ ) |vNext_i,i| {
                        vCurr[i] = vBounceFactor[i] * vNext_i;
                    }
                    xCurr = xNext_;
                }

                // Update from tBounce to tFull
                {
                    var tFull_ = tFull - tBounce;
                    var tHalf_ = 0.5 * tFull_;
                    for ( vCurr ) |vCurr_i,i| {
                        vHalf[i] = vCurr_i + aCurr[i]*tHalf_;
                    }
                    for ( xCurr ) |xCurr_i,i| {
                        xNext[i] = xCurr_i + vHalf[i]*tFull_;
                    }
                    aNext.* = [_]f64 { 0.0 } ** n;
                    for ( accelerators ) |accelerator| {
                        accelerator.addAcceleration( dotIndex, mass, xNext.*, aNext );
                    }
                    for ( vHalf ) |vHalf_i,i| {
                        vNext[i] = vHalf_i + aNext[i]*tHalf_;
                    }
                }
            }
        }

        // Rotate slices
        swapPtrs( f64, &asCurr, &asNext );
        swapPtrs( f64, &vsCurr, &vsNext );
        swapPtrs( f64, &xsCurr, &xsNext );
    }
}

const Accelerator = struct {
    addAccelerationFn: fn ( self: *const Accelerator, dotIndex: usize, mass: f64, x: [2]f64, aSum_OUT: *[2]f64 ) void,

    pub fn addAcceleration( self: *const Accelerator, dotIndex: usize, mass: f64, x: [2]f64, aSum_OUT: *[2]f64 ) void {
        return self.addAccelerationFn( self, dotIndex, mass, x, aSum_OUT );
    }
};

const ConstantAcceleration = struct {
    acceleration: [2]f64,
    accelerator: Accelerator,

    pub fn init( acceleration: [2]f64 ) ConstantAcceleration {
        return ConstantAcceleration {
            .acceleration = acceleration,
            .accelerator = Accelerator {
                .addAccelerationFn = addAcceleration,
            },
        };
    }

    fn addAcceleration( accelerator: *const Accelerator, dotIndex: usize, mass: f64, x: [2]f64, aSum_OUT: *[2]f64 ) void {
        const self = @fieldParentPtr( ConstantAcceleration, "accelerator", accelerator );
        for ( self.acceleration ) |ai,i| {
            aSum_OUT[ i ] += ai;
        }
    }
};

const SpringsAcceleration = struct {
    restLength: f64,
    stiffness: f64,
    allDotCoords: *[]f64,
    accelerator: Accelerator,

    pub fn init( restLength: f64, stiffness: f64, allDotCoords: *[]f64 ) SpringsAcceleration {
        return SpringsAcceleration {
            .restLength = restLength,
            .stiffness = stiffness,
            .allDotCoords = allDotCoords,
            .accelerator = Accelerator {
                .addAccelerationFn = addAcceleration,
            },
        };
    }

    fn addAcceleration( accelerator: *const Accelerator, dotIndex: usize, mass: f64, x: [2]f64, aSum_OUT: *[2]f64 ) void {
        const self = @fieldParentPtr( SpringsAcceleration, "accelerator", accelerator );
        const c1 = self.stiffness / mass;

        const dotFirstCoordIndex = dotIndex * 2;

        const allDotCoords = self.allDotCoords.*;
        var otherFirstCoordIndex = @as( usize, 0 );
        while ( otherFirstCoordIndex < allDotCoords.len ) : ( otherFirstCoordIndex += 2 ) {
            if ( otherFirstCoordIndex != dotFirstCoordIndex ) {
                const xOther = allDotCoords[ otherFirstCoordIndex.. ][ 0..2 ].*;

                var ds = [_]f64 { undefined } ** 2;
                var dSquared = @as( f64, 0.0 );
                for ( xOther ) |xOther_i,i| {
                    const di = xOther_i - x[i];
                    ds[i] = di;
                    dSquared += di*di;
                }
                const d = sqrt( dSquared );

                const offsetFromRest = d - self.restLength;
                const c2 = c1 * offsetFromRest / d;
                for ( ds ) |di,i| {
                    // a = ( stiffness * offsetFromRest * di/d ) / mass
                    aSum_OUT[i] += c2 * di;
                }
            }
        }
    }
};

const Buffer = struct {
    items: []f64,
    size: usize,

    pub fn init( items: []f64 ) Buffer {
        return Buffer {
            .items = items,
            .size = 0,
        };
    }

    pub fn append( self: *Buffer, item: f64 ) void {
        if ( self.size < 0 or self.size >= self.items.len ) {
            std.debug.panic( "Failed to append to buffer: capacity = {d}, size = {d}", .{ self.items.len, self.size } );
        }
        self.items[ self.size ] = item;
        self.size += 1;
    }
};

/// May append up to 2 values to tsWall_OUT.
fn appendBounceTimes( x: f64, v: f64, a: f64, xWall: f64, tsWall_OUT: *Buffer ) void {
    const A = 0.5*a;
    const B = v;
    const C = x - xWall;
    if ( A == 0.0 ) {
        // Bt + C = 0
        const tWall = -C / B;
        tsWall_OUT.append( tWall );
    }
    else {
        // At² + Bt + C = 0
        const D = B*B - 4.0*A*C;
        if ( D >= 0.0 ) {
            const sqrtD = sqrt( D );
            const oneOverTwoA = 0.5 / A;
            const tWallPlus = ( -B + sqrtD )*oneOverTwoA;
            const tWallMinus = ( -B - sqrtD )*oneOverTwoA;
            tsWall_OUT.append( tWallPlus );
            tsWall_OUT.append( tWallMinus );
        }
    }
}

fn swapPtrs( comptime T: type, a: *[]T, b: *[]T ) void {
    const temp = a.ptr;
    a.ptr = b.ptr;
    b.ptr = temp;
}
