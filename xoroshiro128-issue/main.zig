const std = @import( "std" );

pub fn main( ) void {
    // Problem only happens with Xoroshiro128, not other PRNGs
    // Problem happens regardless of PRNG seed
    var x = std.rand.Xoroshiro128.init( 0 );
    var g = &x.random;

    // Problem happens with some array sizes but not others
    var array = [_]i32 { 0, 0 };

    // Prints "0x0, 0x0"
    std.debug.print( "before: 0x{x}, 0x{x}\n", .{ array[0], array[1] } );

    // Problem happens regardless of what PRNG call we make here
    _ = g.int( i32 );

    // Prints "0x13d44fd0, 0x80"
    std.debug.print( " after: 0x{x}, 0x{x}\n", .{ array[0], array[1] } );
}
