const std = @import( "std" );
const Builder = std.build.Builder;

pub fn build( b: *Builder ) void {
    const mode = b.standardReleaseOptions( );

    const exe = b.addExecutable( "sproingy", "src/main.zig" );
    exe.setBuildMode( mode );
    exe.addIncludeDir( "include" );
    exe.addIncludeDir( "/usr/include" );
    exe.addIncludeDir( "/usr/include/GL" );
    exe.linkSystemLibrary( "gtk+-3.0" );
    exe.linkSystemLibrary( "c" );
    exe.linkSystemLibrary( "epoxy" );
    exe.install( );

    b.default_step.dependOn( &exe.step );

    const runStep = b.step( "run", "Run the program" );
    const runCmd = exe.run( );
    runCmd.step.dependOn( b.getInstallStep( ) );
    runStep.dependOn( &runCmd.step );

    const testStep = b.step( "test", "Run all tests" );
    const testFiles = [_][]const u8 {
        "src/util/misc.zig",
    };
    const target = b.standardTargetOptions(.{});
    for ( testFiles ) |f| {
        const testCmd = b.addTest( f );
        testCmd.setTarget( target );
        testCmd.setBuildMode( mode );
        testStep.dependOn( &testCmd.step );
    }
}
