using DecisionProgrammingAlgorithms, TOML, SHA, Dates

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const MASTER_SEED = 2_026_111_100
const INSTANCES_PER_SIZE = 5
const SIZES = 1:5

sha256_file(path) = bytes2hex(sha256(read(path)))

function atomic_toml(path, value)
    mkpath(dirname(path))
    temporary = path * ".$(getpid()).tmp"
    open(io -> TOML.print(io, value; sorted=true), temporary, "w")
    mv(temporary, path; force=true)
end

function campaign_path(argument)
    destination = abspath(argument)
    allowed = joinpath(ROOT, "experiments", "results")
    relpath(destination, allowed) == "." && error("choose a new campaign subdirectory")
    startswith(relpath(destination, allowed), "..") &&
        error("campaign must be below $(allowed)")
    ispath(destination) && error("campaign already exists: $(destination)")
    destination
end

function informative_values(x)
    evaluator = OilEvaluator(x)
    empty_value = operating_value(evaluator, UInt64(0))
    full_value = operating_value(evaluator, full_mask(x))
    empty_value, full_value
end

function generate_campaign(destination)
    mkpath(joinpath(destination, "instances"))
    records = Dict{String,Any}[]
    for m in SIZES
        accepted = 0
        candidate_index = 0
        while accepted < INSTANCES_PER_SIZE
            candidate_index += 1
            candidate_index <= 100_000 || error("candidate seed search exhausted for M=$(m)")
            seed = MASTER_SEED + 100_000 * m + candidate_index
            x = generate_oil(m, seed; kind=:informative)
            empty_value, full_value = informative_values(x)
            full_value > empty_value || continue
            accepted += 1
            id = "seq_info_m$(m)_i$(lpad(accepted, 2, '0'))"
            relative = joinpath("instances", id * ".toml")
            path = joinpath(destination, relative)
            temporary = path * ".$(getpid()).tmp"
            save_oil(temporary, x)
            mv(temporary, path; force=true)
            push!(records, Dict{String,Any}(
                "id" => id,
                "M" => m,
                "seed_id" => accepted,
                "seed" => seed,
                "candidate_index" => candidate_index,
                "generator" => "generate_oil",
                "generator_kind" => "informative",
                "instance_file" => relative,
                "instance_sha256" => instance_hash(x),
                "file_sha256" => sha256_file(path),
                "F_empty_exact" => string(empty_value),
                "F_full_exact" => string(full_value),
                "strictly_informative" => true,
                "states" => size(x.geology, 2),
                "reports" => size(x.reports, 3),
            ))
        end
    end
    manifest = Dict{String,Any}(
        "schema" => "sequential-informative-oil-v1",
        "generated_utc" => string(now(UTC)),
        "master_seed" => MASTER_SEED,
        "generator_call" => "generate_oil(M, seed; kind=:informative)",
        "acceptance_rule" => "operating_value(FULL) > operating_value(EMPTY), exact Rational{BigInt}",
        "sizes" => collect(SIZES),
        "instances_per_size" => INSTANCES_PER_SIZE,
        "records" => records,
    )
    atomic_toml(joinpath(destination, "manifest.toml"), manifest)
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 1 || error("generate.jl CAMPAIGN_DIRECTORY")
    destination = campaign_path(only(ARGS))
    mkpath(dirname(destination))
    staging = destination * ".generating.$(getpid())"
    ispath(staging) && error("generation staging path already exists: $(staging)")
    generate_campaign(staging)
    mv(staging, destination)
    println("Generated 25 hash-recorded instances; no optimization models were built: ", destination)
end
