const std = @import( "std" );
const min = std.math.min;
const max = std.math.max;
const sqrt = std.math.sqrt;
const minInt = std.math.minInt;
const milliTimestamp = std.time.milliTimestamp;
usingnamespace @import( "util/misc.zig" );
usingnamespace @import( "util/axis.zig" );

pub fn SimConfig( comptime N: usize, comptime P: usize ) type {
    return struct {
        updateInterval_MILLIS: i64,
        timestep: f64,
        xLimits: [N]Interval,
        particles: [P]Particle(N),
    };
}

pub fn Particle( comptime N: usize ) type {
    return struct {
        mass: f64,
        x: [N]f64,
        v: [N]f64,

        pub fn init( mass: f64, x: [N]f64, v: [N]f64 ) @This() {
            return .{
                .mass = mass,
                .x = x,
                .v = v,
            };
        }
    };
}

pub const SimControl = struct {
    // Accessed atomically
    _keepRunning: bool = true,

    pub fn init( ) SimControl {
        return SimControl {
            ._keepRunning = false,
        };
    }

    /// Called on simulator thread
    pub fn running( self: *SimControl ) bool {
        return @atomicLoad( bool, &self._keepRunning, .SeqCst );
    }

    /// Called on any thread
    pub fn stop( self: *SimControl ) void {
        @atomicStore( bool, &self._keepRunning, false, .SeqCst );
    }
};

pub const SimListener = struct {
    setParticleCoordsFn: fn ( self: *SimListener, xs: []const f64 ) anyerror!void,

    pub fn setParticleCoords( self: *SimListener, xs: []const f64 ) !void {
        return self.setParticleCoordsFn( self, xs );
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

    var masses = @as( [P]f64, undefined );
    var xsStart = @as( [N*P]f64, undefined );
    var vsStart = @as( [N*P]f64, undefined );
    for ( config.particles ) |particle, p| {
        masses[p] = particle.mass;
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
    var xsCurr = @as( []f64, &coordArrays[0] );
    var xsNext = @as( []f64, &coordArrays[1] );
    var vsCurr = @as( []f64, &coordArrays[2] );
    var vsHalf = @as( []f64, &coordArrays[3] );
    var vsNext = @as( []f64, &coordArrays[4] );
    var asCurr = @as( []f64, &coordArrays[5] );
    var asNext = @as( []f64, &coordArrays[6] );

    // TODO: Get accelerators from config
    var gravity = ConstantAcceleration(N).init( [_]f64 { 0.0, -9.80665 } );
    var springs = SpringsAcceleration(N).init( 0.6, 300.0, &xsCurr );
    const accelerators = [_]*Accelerator(N) { &gravity.accelerator, &springs.accelerator };

    xsCurr[ 0..N*P ].* = xsStart;
    vsCurr[ 0..N*P ].* = vsStart;
    for ( particleFirstCoordIndices ) |c0, p| {
        const xCurr = xsCurr[ c0.. ][ 0..N ];
        var aCurr = asCurr[ c0.. ][ 0..N ];
        aCurr.* = [1]f64 { 0.0 } ** N;
        for ( accelerators ) |accelerator| {
            accelerator.addAcceleration( p, masses[p], xCurr.*, aCurr );
        }
    }

    const updateInterval_MILLIS = config.updateInterval_MILLIS;
    var nextUpdate_PMILLIS = @as( i64, minInt( i64 ) );
    while ( running.get( ) ) {
        // Send particle coords to the listener periodically
        const now_PMILLIS = milliTimestamp( );
        if ( now_PMILLIS >= nextUpdate_PMILLIS ) {
            try listener.setParticleCoords( xsCurr );
            nextUpdate_PMILLIS = now_PMILLIS + updateInterval_MILLIS;
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
                accelerator.addAcceleration( p, masses[p], xNext.*, aNext );
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

            const mass = masses[ p ];

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
                        accelerator.addAcceleration( p, mass, xNext_, &aNext_ );
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
                        accelerator.addAcceleration( p, mass, xNext.*, aNext );
                    }
                    for ( vHalf ) |vHalf_n, n| {
                        vNext[n] = vHalf_n + aNext[n]*tHalf_;
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

pub fn Accelerator( comptime N: usize ) type {
    return struct {
        addAccelerationFn: fn ( self: *const @This(), p: usize, mass: f64, x: [N]f64, aSum_OUT: *[N]f64 ) void,

        pub fn addAcceleration( self: *const @This(), p: usize, mass: f64, x: [N]f64, aSum_OUT: *[N]f64 ) void {
            return self.addAccelerationFn( self, p, mass, x, aSum_OUT );
        }
    };
}

pub fn ConstantAcceleration( comptime N: usize ) type {
    return struct {
        acceleration: [N]f64,
        accelerator: Accelerator(N),

        pub fn init( acceleration: [N]f64 ) @This() {
            return .{
                .acceleration = acceleration,
                .accelerator = .{
                    .addAccelerationFn = addAcceleration,
                },
            };
        }

        fn addAcceleration( accelerator: *const Accelerator(N), p: usize, mass: f64, x: [N]f64, aSum_OUT: *[N]f64 ) void {
            const self = @fieldParentPtr( @This(), "accelerator", accelerator );
            for ( self.acceleration ) |a_n, n| {
                aSum_OUT[n] += a_n;
            }
        }
    };
}

pub fn SpringsAcceleration( comptime N: usize ) type {
    return struct {
        restLength: f64,
        stiffness: f64,
        allParticleCoords: *[]f64,
        accelerator: Accelerator(N),

        pub fn init( restLength: f64, stiffness: f64, allParticleCoords: *[]f64 ) @This() {
            return .{
                .restLength = restLength,
                .stiffness = stiffness,
                .allParticleCoords = allParticleCoords,
                .accelerator = .{
                    .addAccelerationFn = addAcceleration,
                },
            };
        }

        fn addAcceleration( accelerator: *const Accelerator(N), p: usize, mass: f64, x: [N]f64, aSum_OUT: *[N]f64 ) void {
            const self = @fieldParentPtr( @This(), "accelerator", accelerator );
            const c1 = self.stiffness / mass;

            const c0 = p * N;

            const allParticleCoords = self.allParticleCoords.*;
            var b0 = @as( usize, 0 );
            while ( b0 < allParticleCoords.len ) : ( b0 += N ) {
                if ( b0 != c0 ) {
                    const xOther = allParticleCoords[ b0.. ][ 0..N ];

                    var ds = @as( [N]f64, undefined );
                    var dSquared = @as( f64, 0.0 );
                    for ( xOther ) |xOther_n, n| {
                        const d_n = xOther_n - x[n];
                        ds[n] = d_n;
                        dSquared += d_n * d_n;
                    }
                    const d = sqrt( dSquared );

                    const offsetFromRest = d - self.restLength;
                    const c2 = c1 * offsetFromRest / d;
                    for ( ds ) |d_n, n| {
                        // a = ( stiffness * offsetFromRest * dn/d ) / mass
                        aSum_OUT[n] += c2 * d_n;
                    }
                }
            }
        }
    };
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

fn swapPtrs( comptime T: type, a: *[]T, b: *[]T ) void {
    const temp = a.ptr;
    a.ptr = b.ptr;
    b.ptr = temp;
}
