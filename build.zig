const std = @import("std");

pub fn build(b: *std.Build) !void {
    const kernelc = addInstall(b);
    addTests(b, kernelc);
}

fn addInstall(b: *std.Build) KernelCompile {
    const kernel = b.addExecutable(.{
        .name = "ross",
        .code_model = .kernel,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.standardTargetOptions(.{
                .default_target = .{
                    .cpu_arch = .x86,
                    .os_tag = .freestanding,
                    .abi = .none,
                    .cpu_features_add = blk: {
                        var res = std.Target.Cpu.Feature.Set.empty;
                        res.addFeature(@intFromEnum(std.Target.x86.Feature.soft_float));

                        break :blk res;
                    },
                    .cpu_features_sub = blk: {
                        var res = std.Target.Cpu.Feature.Set.empty;
                        res.addFeature(@intFromEnum(std.Target.x86.Feature.mmx));
                        res.addFeature(@intFromEnum(std.Target.x86.Feature.sse));
                        res.addFeature(@intFromEnum(std.Target.x86.Feature.sse2));
                        res.addFeature(@intFromEnum(std.Target.x86.Feature.avx));
                        res.addFeature(@intFromEnum(std.Target.x86.Feature.avx2));

                        break :blk res;
                    },
                },
            }),
            .optimize = b.standardOptimizeOption(.{}),
            .link_libc = false,
            .link_libcpp = false,
            .dwarf_format = .@"32",

            // Disable red zone to prevent stack-clobbering nonsense in IRQ handlers.
            .red_zone = false,
        }),
    });
    kernel.entry = .{ .symbol_name = "_kmain" };
    kernel.setLinkerScript(b.path("src/asm/link.ld"));
    kernel.link_gc_sections = false;

    const build_asm_lib, const asm_lib_obj = blk: {
        const build_loader = std.Build.Step.Run.create(b, "Build asm lib");
        build_loader.addArgs(&.{
            "nasm",
            "-f",
            "elf32",
            "-o",
        });
        const loader_obj = build_loader.addOutputFileArg("asm_fns.o");
        build_loader.addFileArg(b.path("src/asm/asm.s"));

        break :blk .{ build_loader, loader_obj };
    };
    kernel.step.dependOn(&build_asm_lib.step);
    kernel.root_module.addObjectFile(asm_lib_obj);

    b.installArtifact(kernel);

    return .{ .kernel = kernel, .asm_lib_obj = asm_lib_obj };
}

const KernelCompile = struct {
    kernel: *std.Build.Step.Compile,
    asm_lib_obj: std.Build.LazyPath,
};

fn addTests(b: *std.Build, kernelc: KernelCompile) void {
    const exe_unit_tests = b.addTest(.{
        .root_module = kernelc.kernel.root_module,
    });
    exe_unit_tests.linker_script = kernelc.kernel.linker_script;

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
