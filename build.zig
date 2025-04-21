const std = @import("std");
const fs = std.fs;

pub fn build(b: *std.Build) !void {
    const build_iso = b.option(bool, "build-iso", "build a bootable iso") orelse false;

    const exe = addExe(b);
    if (build_iso) {
        addBuildIso(b, exe);
    }

    addTests(b, exe.root_module);
}

fn addExe(b: *std.Build) *std.Build.Step.Compile {
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = b.standardTargetOptions(.{
            .default_target = .{
                .cpu_arch = .x86,
                .os_tag = .freestanding,
                .ofmt = .elf,
                .abi = .none,
            },
        }),
        .optimize = b.standardOptimizeOption(.{}),
    });

    const exe = b.addExecutable(.{
        .name = "ross",
        .root_module = exe_mod,
        .linkage = .static,
    });
    exe.entry = .{ .symbol_name = "_kmain" };
    exe.setLinkerScript(b.path("boot/link.ld"));

    b.installArtifact(exe);

    return exe;
}

fn addTests(b: *std.Build, exe_mod: *std.Build.Module) void {
    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

fn addBuildIso(b: *std.Build, exe: *std.Build.Step.Compile) void {
    const step = b.step("build-iso", "Build iso");
    const copy_files = b.addWriteFiles();
    const mkisofs = std.Build.Step.Run.create(b, "mkisofs");

    step.dependOn(&mkisofs.step);
    mkisofs.step.dependOn(&copy_files.step);
    copy_files.step.dependOn(&exe.step);

    // Copy files to the iso staging dir.
    _ = copy_files.addCopyFile(b.path("boot/stage2_eltorito"), "out/iso/boot/grub/stage2_eltorito");
    _ = copy_files.addCopyFile(b.path("boot/menu.lst"), "out/iso/boot/grub/menu.lst");
    const kernel_elf_file = copy_files.addCopyFile(b.path("zig-out/bin/ross"), "out/iso/boot/kernel.elf");
    const iso_dir = kernel_elf_file.path(b, "../../");

    // Run mkisofs on iso staging dir.
    mkisofs.addArgs(&.{
        "mkisofs",
        "-quiet",
        "-input-charset",
        "utf8",
        "-eltorito-boot",
        "boot/grub/stage2_eltorito",
        "-boot-info-table",
        "-boot-load-size",
        "4",
        "-rock",
        "-no-emul-boot",
        "-A",
        "os",
    });

    mkisofs.addArg("-o");
    const iso_file = mkisofs.addOutputFileArg(b.path("out/os.iso").getPath(b));

    mkisofs.addDirectoryArg(iso_dir);

    _ = b.addInstallFile(iso_file, "os.iso");
}
