const std = @import( "std" );
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

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
