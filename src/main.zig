const std = @import( "std" );
const sqrt = std.math.sqrt;
const Atomic = std.atomic.Atomic;
const Allocator = std.mem.Allocator;
usingnamespace @import( "core/util.zig" );
usingnamespace @import( "core/core.zig" );
usingnamespace @import( "core/gtkz.zig" );
usingnamespace @import( "core/support.zig" );
usingnamespace @import( "space/view.zig" );
usingnamespace @import( "space/dots.zig" );
usingnamespace @import( "time/view.zig" );
usingnamespace @import( "time/curve.zig" );
usingnamespace @import( "sim.zig" );

// Allow async/await to use multiple threads
pub const io_mode = .evented;

fn doRunSimulation( comptime N: usize, comptime P: usize, config: *const SimConfig(N,P), listeners: []const *SimListener(N,P), running: *const Atomic(bool) ) !void {
    // Indicate to the async/await mechanism that we're going to monopolize a thread
    std.event.Loop.startCpuBoundOperation( );
    try runSimulation( N, P, config, listeners, running );
}

fn ConstantAcceleration( comptime N: usize, comptime P: usize ) type {
    return struct {
        const Self = @This();

        acceleration: [N]f64,
        xLimits: [N]Interval,

        accelerator: Accelerator(N,P) = .{
            .addAccelerationFn = addAcceleration,
            .computePotentialEnergyFn = computePotentialEnergy,
        },

        pub fn init( acceleration: [N]f64, xLimits: [N]Interval ) Self {
            return .{
                .acceleration = acceleration,
                .xLimits = xLimits,
            };
        }

        fn addAcceleration( accelerator: *const Accelerator(N,P), xs: *const [N*P]f64, ms: *const [P]f64, p: usize, x: [N]f64, aSum_OUT: *[N]f64 ) void {
            const self = @fieldParentPtr( Self, "accelerator", accelerator );
            for ( self.acceleration ) |a_n, n| {
                aSum_OUT[n] += a_n;
            }
        }

        fn computePotentialEnergy( accelerator: *const Accelerator(N,P), xs: *const [N*P]f64, ms: *const [P]f64 ) f64 {
            const self = @fieldParentPtr( Self, "accelerator", accelerator );
            const a = self.acceleration;

            var xZeroPotential = @as( [N]f64, undefined );
            for ( a ) |a_n, n| {
                if ( a_n < 0 ) {
                    xZeroPotential[n] = self.xLimits[n].start;
                }
                else {
                    xZeroPotential[n] = self.xLimits[n].end( );
                }
            }

            var totalPotentialEnergy = @as( f64, 0.0 );
            for ( ms ) |m, p| {
                for ( a ) |a_n, n| {
                    const x_n = xs[ p*N + n ];
                    totalPotentialEnergy += m * -a_n * ( x_n - xZeroPotential[n] );
                }
            }
            return totalPotentialEnergy;
        }
    };
}

fn SpringsAcceleration( comptime N: usize, comptime P: usize ) type {
    return struct {
        const Self = @This();

        restLength: f64,
        stiffness: f64,
        accelerator: Accelerator(N,P),

        pub fn init( restLength: f64, stiffness: f64 ) Self {
            return .{
                .restLength = restLength,
                .stiffness = stiffness,
                .accelerator = .{
                    .addAccelerationFn = addAcceleration,
                    .computePotentialEnergyFn = computePotentialEnergy,
                },
            };
        }

        fn addAcceleration( accelerator: *const Accelerator(N,P), xs: *const [N*P]f64, ms: *const [P]f64, p: usize, x: [N]f64, aSum_OUT: *[N]f64 ) void {
            const self = @fieldParentPtr( Self, "accelerator", accelerator );
            const stiffnessOverMass = self.stiffness / ms[p];

            const pA = p;
            const xA = x;
            var pB = @as( usize, 0 );
            while ( pB < P ) : ( pB += 1 ) {
                if ( pB != pA ) {
                    const xB = xs[ pB*N.. ][ 0..N ];

                    var d = @as( [N]f64, undefined );
                    var dMagSquared = @as( f64, 0.0 );
                    for ( xB ) |xB_n, n| {
                        const d_n = xB_n - xA[n];
                        d[n] = d_n;
                        dMagSquared += d_n * d_n;
                    }
                    const dMag = sqrt( dMagSquared );
                    const offsetFromRest = dMag - self.restLength;

                    const factor = stiffnessOverMass * offsetFromRest / dMag;
                    for ( d ) |d_n, n| {
                        // F = stiffness * offsetFromRest * d[n]/dMag
                        // a = F / m
                        //   = ( stiffness * offsetFromRest * d[n]/dMag ) / m
                        //   = ( stiffness / m )*( offsetFromRest / dMag )*d[n]
                        aSum_OUT[n] += factor * d_n;
                    }
                }
            }
        }

        fn computePotentialEnergy( accelerator: *const Accelerator(N,P), xs: *const [N*P]f64, ms: *const [P]f64 ) f64 {
            const self = @fieldParentPtr( Self, "accelerator", accelerator );
            const halfStiffness = 0.5 * self.stiffness;

            var totalPotentialEnergy = @as( f64, 0.0 );

            var pA = @as( usize, 0 );
            while ( pA < P ) : ( pA += 1 ) {
                const xA = xs[ pA*N.. ][ 0..N ];

                var pB = @as( usize, pA + 1 );
                while ( pB < P ) : ( pB += 1 ) {
                    const xB = xs[ pB*N.. ][ 0..N ];

                    var d = @as( [N]f64, undefined );
                    var dMagSquared = @as( f64, 0.0 );
                    for ( xB ) |xB_n, n| {
                        const d_n = xB_n - xA[n];
                        d[n] = d_n;
                        dMagSquared += d_n * d_n;
                    }
                    const dMag = sqrt( dMagSquared );
                    const offsetFromRest = dMag - self.restLength;

                    totalPotentialEnergy += halfStiffness * offsetFromRest*offsetFromRest;
                }
            }

            return totalPotentialEnergy;
        }
    };
}

fn WidgetRepainter( comptime N: usize, comptime P: usize ) type {
    return struct {
        const Self = @This();

        widgets: []const *GtkWidget,

        simListener: SimListener(N,P) = SimListener(N,P) {
            .handleFrameFn = handleFrame,
        },

        pub fn init( widgets: []const *GtkWidget ) Self {
            return Self {
                .widgets = widgets,
            };
        }

        /// Called on simulator thread
        fn handleFrame( simListener: *SimListener(N,P), frame: *const SimFrame(N,P) ) !void {
            const self = @fieldParentPtr( Self, "simListener", simListener );
            for ( self.widgets ) |widget| {
                gtk_widget_queue_draw( widget );
            }
        }
    };
}

pub fn main( ) !void {
    var gpa = std.heap.GeneralPurposeAllocator( .{} ) {};
    const allocator = &gpa.allocator;

    const N = 2;
    const P = 3;

    const xLimits = [N]Interval {
        Interval.initStartEnd( -8, 8 ),
        Interval.initStartEnd( -6, 6 ),
    };

    var gravity = ConstantAcceleration(N,P).init( [N]f64 { 0.0, -9.80665 }, xLimits );
    var springs = SpringsAcceleration(N,P).init( 0.6, 300.0 );
    var accelerators = [_]*const Accelerator(N,P) {
        &gravity.accelerator,
        &springs.accelerator,
    };

    const simConfig = SimConfig(N,P) {
        .frameInterval_MILLIS = 15,
        .timestep = 500e-9,
        .xLimits = xLimits,
        .particles = [P]Particle(N) {
            Particle(N).init( 1, [N]f64{ -6.0, -3.0 }, [N]f64{ 7.0, 13.0 } ),
            Particle(N).init( 1, [N]f64{ -6.5, -3.0 }, [N]f64{ 2.0, 14.0 } ),
            Particle(N).init( 1, [N]f64{ -6.1, -3.2 }, [N]f64{ 5.0,  6.0 } ),
        },
        .accelerators = &accelerators,
    };

    try gtkzInit( allocator );

    var timeView = @as( TimeView(N,P), undefined );
    try timeView.init( allocator );
    defer timeView.deinit( );

    var spaceView = @as( SpaceView(N,P), undefined );
    try spaceView.init( &simConfig.xLimits, &timeView.cursor, allocator );
    defer spaceView.deinit( );

    const splitter = gtk_paned_new( .GTK_ORIENTATION_VERTICAL );
    gtk_paned_set_wide_handle( @ptrCast( *GtkPaned, splitter ), 1 );
    gtk_paned_pack1( @ptrCast( *GtkPaned, splitter ), spaceView.glArea, 1, 1 );
    gtk_paned_pack2( @ptrCast( *GtkPaned, splitter ), timeView.glArea, 1, 1 );
    gtk_widget_set_size_request( spaceView.glArea, -1, 70 );
    gtk_widget_set_size_request( timeView.glArea, -1, 30 );

    const window = gtk_window_new( .GTK_WINDOW_TOPLEVEL );
    gtk_container_add( @ptrCast( *GtkContainer, window ), splitter );
    gtk_window_set_title( @ptrCast( *GtkWindow, window ), "Sproingy" );
    gtk_window_set_default_size( @ptrCast( *GtkWindow, window ), 480, 360 );

    const fullscreenKeys = [_]guint { GDK_KEY_f, GDK_KEY_F11 };
    var fullscreenKeysHandler = FullscreenKeysHandler.init( &fullscreenKeys );
    _ = try gtkzConnectHandler( spaceView.glArea, "key-press-event", FullscreenKeysHandler.onKeyDown, &fullscreenKeysHandler );
    _ = try gtkzConnectHandler( timeView.glArea, "key-press-event", FullscreenKeysHandler.onKeyDown, &fullscreenKeysHandler );

    const closeKeys = [_]guint { GDK_KEY_Escape };
    var closeKeysHandler = CloseKeysHandler.init( &closeKeys );
    _ = try gtkzConnectHandler( spaceView.glArea, "key-press-event", CloseKeysHandler.onKeyDown, &closeKeysHandler );
    _ = try gtkzConnectHandler( timeView.glArea, "key-press-event", CloseKeysHandler.onKeyDown, &closeKeysHandler );

    var quittingHandler = QuittingHandler.init( );
    _ = try gtkzConnectHandler( window, "delete-event", QuittingHandler.onWindowClosing, &quittingHandler );
    _ = try gtkzConnectHandler( window, "delete-event", PaintingHandler.onWindowClosing, &timeView.paintingHandler );
    _ = try gtkzConnectHandler( window, "delete-event", PaintingHandler.onWindowClosing, &spaceView.paintingHandler );

    const widgets = [_]*GtkWidget { splitter };
    var repainter = WidgetRepainter(N,P).init( &widgets );

    const simListeners = [_]*SimListener(N,P) {
        &spaceView.dotsPaintable.simListener,
        &timeView.curvePaintable.simListener,
        &repainter.simListener,
    };

    var simRunning = Atomic( bool ).init( true );
    var simFrame = async doRunSimulation( N, P, &simConfig, &simListeners, &simRunning );

    gtk_widget_show_all( window );
    gtk_main( );

    // Main-thread stack needs to stay valid until sim-thread exits
    simRunning.store( false, .SeqCst );
    try await simFrame;
}
