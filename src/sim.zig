const std = @import( "std" );
const min = std.math.min;
const max = std.math.max;
const sqrt = std.math.sqrt;
const minInt = std.math.minInt;
const Atomic = std.atomic.Atomic;
const milliTimestamp = std.time.milliTimestamp;
usingnamespace @import( "core/util.zig" );

pub fn SimConfig( comptime N: usize, comptime P: usize ) type {
    return struct {
        frameInterval_MILLIS: i64,
        timestep: f64,
        xLimits: [N]Interval,
        particles: [P]Particle(N),
        accelerators: []*const Accelerator(N,P),
    };
}

pub fn Accelerator( comptime N: usize, comptime P: usize ) type {
    return struct {
        const Self = @This();

        addAccelerationFn: fn ( self: *const Self, xs: *const [N*P]f64, ms: [P]f64, p: usize, xp: [N]f64, aSum_OUT: *[N]f64 ) void,

        pub fn addAcceleration( self: *const Self, xs: *const [N*P]f64, ms: [P]f64, p: usize, xp: [N]f64, aSum_OUT: *[N]f64 ) void {
            return self.addAccelerationFn( self, xs, ms, p, xp, aSum_OUT );
        }
    };
}

pub fn Particle( comptime N: usize ) type {
    return struct {
        const Self = @This();

        m: f64,
        x: [N]f64,
        v: [N]f64,

        pub fn init( m: f64, x: [N]f64, v: [N]f64 ) Self {
            return .{
                .m = m,
                .x = x,
                .v = v,
            };
        }
    };
}

pub const SimListener = struct {
    const Self = @This();

    addFrameFn: fn ( self: *Self, t: f64, N: usize, xs: []const f64 ) anyerror!void,

    pub fn addFrame( self: *Self, t: f64, N: usize, xs: []const f64 ) !void {
        return self.addFrameFn( self, t, N, xs );
    }
};

/// Caller must ensure that locations pointed to by input
/// args remain valid until after this fn returns.
pub fn runSimulation(
    comptime N: usize,
    comptime P: usize,
    config: *const SimConfig(N,P),
    listener: *SimListener,
    running: *const Atomic(bool),
) !void {
    // TODO: Use SIMD Vectors?
    // TODO: Multi-thread? (If so, avoid false sharing)

    // TODO: Understand why this magic makes async/await work sensibly
    std.event.Loop.startCpuBoundOperation( );

    const tFull = config.timestep;
    const tHalf = 0.5*tFull;
    const accelerators = config.accelerators;

    var ms = @as( [P]f64, undefined );
    var xsStart = @as( [N*P]f64, undefined );
    var vsStart = @as( [N*P]f64, undefined );
    for ( config.particles ) |particle, p| {
        ms[p] = particle.m;
        xsStart[ p*N.. ][ 0..N ].* = particle.x;
        vsStart[ p*N.. ][ 0..N ].* = particle.v;
    }

    var xMins = @as( [N]f64, undefined );
    var xMaxs = @as( [N]f64, undefined );
    for ( config.xLimits ) |xLimit, n| {
        const xLimitA = xLimit.start;
        const xLimitB = xLimit.start + xLimit.span;
        xMins[n] = min( xLimitA, xLimitB );
        xMaxs[n] = max( xLimitA, xLimitB );
    }

    // Pre-compute the index of the first coord of each particle, for easy iteration later
    var particleFirstCoordIndices = @as( [P]usize, undefined ); {
        var p = @as( usize, 0 );
        while ( p < P ) : ( p += 1 ) {
            particleFirstCoordIndices[p] = p * N;
        }
    }

    var coordArrays = @as( [7][N*P]f64, undefined );
    var xsCurr = &coordArrays[0];
    var xsNext = &coordArrays[1];
    var vsCurr = &coordArrays[2];
    var vsHalf = &coordArrays[3];
    var vsNext = &coordArrays[4];
    var asCurr = &coordArrays[5];
    var asNext = &coordArrays[6];

    xsCurr[ 0..N*P ].* = xsStart;
    vsCurr[ 0..N*P ].* = vsStart;
    for ( particleFirstCoordIndices ) |c0, p| {
        const xCurr = xsCurr[ c0.. ][ 0..N ];
        var aCurr = asCurr[ c0.. ][ 0..N ];
        aCurr.* = [1]f64 { 0.0 } ** N;
        for ( accelerators ) |accelerator| {
            accelerator.addAcceleration( xsCurr, ms, p, xCurr.*, aCurr );
        }
    }

    const frameInterval_MILLIS = config.frameInterval_MILLIS;
    var nextFrame_PMILLIS = @as( i64, minInt( i64 ) );
    var tElapsed = @as( f64, 0 );
    while ( running.load( .SeqCst ) ) : ( tElapsed += tFull ) {
        // Send particle coords to the listener periodically
        const now_PMILLIS = milliTimestamp( );
        if ( now_PMILLIS >= nextFrame_PMILLIS ) {
            try listener.addFrame( tElapsed, N, xsCurr );
            nextFrame_PMILLIS = now_PMILLIS + frameInterval_MILLIS;
        }

        // Update particle coords, but without checking for bounces
        for ( vsCurr ) |vCurr, c| {
            vsHalf[c] = vCurr + asCurr[c]*tHalf;
        }
        for ( xsCurr ) |xCurr, c| {
            xsNext[c] = xCurr + vsHalf[c]*tFull;
        }
        for ( particleFirstCoordIndices ) |c0, p| {
            var xNext = xsNext[ c0.. ][ 0..N ];
            var aNext = asNext[ c0.. ][ 0..N ];
            aNext.* = [1]f64 { 0.0 } ** N;
            for ( accelerators ) |accelerator| {
                accelerator.addAcceleration( xsCurr, ms, p, xNext.*, aNext );
            }
        }
        for ( vsHalf ) |vHalf, c| {
            vsNext[c] = vHalf + asNext[c]*tHalf;
        }

        // Handle bounces
        for ( particleFirstCoordIndices ) |c0, p| {
            // TODO: Profile, speed up
            var xNext = xsNext[ c0.. ][ 0..N ];

            // Bail immediately in the common case with no bounce
            var hasBounce = false;
            for ( xNext ) |xNext_n, n| {
                if ( xNext_n <= xMins[n] or xNext_n >= xMaxs[n] ) {
                    hasBounce = true;
                    break;
                }

                const aCurr_n = asCurr[ c0 + n ];
                const vCurr_n = vsCurr[ c0 + n ];
                const tTip_n = vCurr_n / ( -2.0 * aCurr_n );
                if ( 0 <= tTip_n and tTip_n < tFull ) {
                    const xCurr_n = xsCurr[ c0 + n ];
                    const xTip_n = xCurr_n + vCurr_n*tTip_n + 0.5*aCurr_n*tTip_n*tTip_n;
                    if ( xTip_n <= xMins[n] or xTip_n >= xMaxs[n] ) {
                        hasBounce = true;
                        break;
                    }
                }
            }
            if ( !hasBounce ) {
                continue;
            }

            var aNext = asNext[ c0.. ][ 0..N ];
            var vNext = vsNext[ c0.. ][ 0..N ];
            var vHalf = vsHalf[ c0.. ][ 0..N ];

            var aCurr = @as( [N]f64, undefined );
            var vCurr = @as( [N]f64, undefined );
            var xCurr = @as( [N]f64, undefined );
            aCurr = asCurr[ c0.. ][ 0..N ].*;
            vCurr = vsCurr[ c0.. ][ 0..N ].*;
            xCurr = xsCurr[ c0.. ][ 0..N ].*;

            while ( true ) {
                // Time of soonest bounce, and what to multiply each velocity coord by at that time
                var tBounce = std.math.inf( f64 );
                var vBounceFactor = [1]f64 { 1.0 } ** N;
                for ( xNext ) |xNext_n, n| {
                    var hasMinBounce = false;
                    var hasMaxBounce = false;

                    if ( xNext_n <= xMins[n] ) {
                        hasMinBounce = true;
                    }
                    else if ( xNext_n >= xMaxs[n] ) {
                        hasMaxBounce = true;
                    }

                    const tTip_n = vCurr[n] / ( -2.0 * aCurr[n] );
                    if ( 0 <= tTip_n and tTip_n < tFull ) {
                        const xTip_n = xCurr[n] + vCurr[n]*tTip_n + 0.5*aCurr[n]*tTip_n*tTip_n;
                        if ( xTip_n <= xMins[n] ) {
                            hasMinBounce = true;
                        }
                        else if ( xTip_n >= xMaxs[n] ) {
                            hasMaxBounce = true;
                        }
                    }

                    // At most 4 bounce times will be appended
                    var tsBounce_n_ = @as( [4]f64, undefined );
                    var tsBounce_n = Buffer.init( &tsBounce_n_ );
                    if ( hasMinBounce ) {
                        appendBounceTimes( xCurr[n], vCurr[n], aCurr[n], xMins[n], &tsBounce_n );
                    }
                    if ( hasMaxBounce ) {
                        appendBounceTimes( xCurr[n], vCurr[n], aCurr[n], xMaxs[n], &tsBounce_n );
                    }
                    for ( tsBounce_n.items[ 0..tsBounce_n.size ] ) |tBounce_n| {
                        if ( 0 <= tBounce_n and tBounce_n < tFull ) {
                            if ( tBounce_n < tBounce ) {
                                tBounce = tBounce_n;
                                vBounceFactor = [1]f64 { 1.0 } ** N;
                                vBounceFactor[n] = -1.0;
                            }
                            else if ( tBounce_n == tBounce ) {
                                vBounceFactor[n] = -1.0;
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
                    var aNext_ = @as( [N]f64, undefined );
                    var vNext_ = @as( [N]f64, undefined );
                    var xNext_ = @as( [N]f64, undefined );
                    for ( vCurr ) |vCurr_n, n| {
                        vHalf[n] = vCurr_n + aCurr[n]*tHalf_;
                    }
                    for ( xCurr ) |xCurr_n, n| {
                        xNext_[n] = xCurr_n + vHalf[n]*tFull_;
                    }
                    aNext_ = [1]f64 { 0.0 } ** N;
                    for ( accelerators ) |accelerator| {
                        accelerator.addAcceleration( xsCurr, ms, p, xNext_, &aNext_ );
                    }
                    for ( vHalf ) |vHalf_n, n| {
                        vNext_[n] = vHalf_n + aNext_[n]*tHalf_;
                    }

                    aCurr = aNext_;
                    for ( vNext_ ) |vNext_n, n| {
                        vCurr[n] = vBounceFactor[n] * vNext_n;
                    }
                    xCurr = xNext_;
                }

                // Update from tBounce to tFull
                {
                    var tFull_ = tFull - tBounce;
                    var tHalf_ = 0.5 * tFull_;
                    for ( vCurr ) |vCurr_n, n| {
                        vHalf[n] = vCurr_n + aCurr[n]*tHalf_;
                    }
                    for ( xCurr ) |xCurr_n, n| {
                        xNext[n] = xCurr_n + vHalf[n]*tFull_;
                    }
                    aNext.* = [1]f64 { 0.0 } ** N;
                    for ( accelerators ) |accelerator| {
                        accelerator.addAcceleration( xsCurr, ms, p, xNext.*, aNext );
                    }
                    for ( vHalf ) |vHalf_n, n| {
                        vNext[n] = vHalf_n + aNext[n]*tHalf_;
                    }
                }
            }
        }

        // Rotate slices
        swap( *[N*P]f64, &asCurr, &asNext );
        swap( *[N*P]f64, &vsCurr, &vsNext );
        swap( *[N*P]f64, &xsCurr, &xsNext );
    }
}

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

fn swap( comptime T: type, a: *T, b: *T ) void {
    const temp = a.*;
    a.* = b.*;
    b.* = temp;
}
