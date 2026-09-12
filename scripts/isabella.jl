#!/usr/bin/env julia
#
# isabella.jl
#
# One command to turn a YAML controller description into a project tree.
# Replaces the julia-then-yq-then-bash dance in scripts/controller_project,
# which needed yq and realpath and so never ran on Windows.
#
#   julia --project=. scripts/isabella.jl examples/controller_with_shift.yaml
#   julia --project=. scripts/isabella.jl my.yaml -o build/mine
#   julia --project=. scripts/isabella.jl my.yaml --force
#
# sara, 9/5/26

using ArgParse
using YAML

include(joinpath(@__DIR__, "..", "src", "Isabella.jl"))
using .Isabella


# the safety checks from the old bash script, minus the realpath dependency.
# generated names come out of the YAML, so a bad module: field could otherwise
# scribble outside the project directory.
function safe_relative(name)
    occursin(r"[\\]", name)            && return false     # backslashes
    occursin("..", name)               && return false     # traversal
    startswith(name, "/")              && return false     # absolute
    occursin(r"^[A-Za-z]:", name)      && return false     # windows drive
    for part in split(name, "/")
        isempty(part) && return false
        occursin(r"^[A-Za-z0-9._-]+$", part) || return false
    end
    return true
end


function parse_commandline()
    s = ArgParseSettings(
        prog        = "isabella.jl",
        description = "Generate a programmable controller project from a YAML description.")
    @add_arg_table! s begin
        "yaml"
            help     = "YAML file describing the controller"
            required = true
        "--out", "-o"
            help    = "output directory (default: the module name from the YAML)"
            default = nothing
        "--force", "-f"
            help   = "overwrite an existing directory without asking"
            action = :store_true
        "--quiet", "-q"
            help   = "only report problems"
            action = :store_true
    end
    return parse_args(s)
end


function main()
    args = parse_commandline()
    src  = args["yaml"]

    isfile(src) || begin
        println(stderr, "error: no such file: ", src)
        return 1
    end

    local data
    try
        data = YAML.load_file(src)
    catch e
        println(stderr, "error: could not parse ", src, " as YAML")
        println(stderr, "  ", sprint(showerror, e))
        return 1
    end

    # sara (9/6): only checked four, so a yaml missing rst: threw a raw KeyError
    #for k in ("module", "commands", "hex_prefix", "program")
    for k in ("module", "commands", "hex_prefix", "program",
              "inputs", "outputs", "initial", "rst")
        haskey(data, k) || begin
            println(stderr, "error: ", src, " has no `", k, ":` field")
            return 1
        end
    end

    modname = string(data["module"])
    safe_relative(modname) || begin
        println(stderr, "error: module name is not usable as a directory: ", modname)
        return 1
    end

    outdir = args["out"] === nothing ? modname : args["out"]

    if isdir(outdir) && !args["force"]
        print("Directory $(outdir)/ exists. Overwrite? (y/n): ")
        flush(stdout)
        ans = strip(something(readline(), ""))
        if lowercase(ans) != "y"
            println("Nothing written.")
            return 0
        end
    end

    # generate_controller_project throws on bad input (unknown command, bad
    # address label, program too long, too many commands). catch it here so
    # students get the message instead of a stacktrace.
    local files
    try
        files = Isabella.generate_controller_project(data)
    catch e
        if isa(e, ErrorException)
            println(stderr, "error: ", e.msg)
        else
            println(stderr, "error: ", sprint(showerror, e))
        end
        return 1
    end

    for f in files
        safe_relative(f["filename"]) || begin
            println(stderr, "error: generated a bad filename: ", f["filename"])
            return 1
        end
    end

    for f in files
        path = joinpath(outdir, f["filename"])
        mkpath(dirname(path))
        open(path, "w") do io
            write(io, f["contents"])
        end
        args["quiet"] || println("  ", path)
    end

    if !args["quiet"]
        println()
        println(length(files), " files written to ", outdir, "/")
        println()
        println("next: add ", joinpath(outdir, "src"), "/*.sv and inc/ to your Vivado project.")
        println("      the .mem is read relative to the simulation working directory.")
    end
    return 0
end

exit(main())
