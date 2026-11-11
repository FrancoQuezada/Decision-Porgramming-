using DecisionProgrammingAlgorithms, TOML, SHA

sha256_file(path) = bytes2hex(sha256(read(path)))

function exact_values(x)
    evaluator = OilEvaluator(x)
    operating_value(evaluator, UInt64(0)), operating_value(evaluator, full_mask(x))
end

function validate_campaign(destination)
    manifest = TOML.parsefile(joinpath(destination, "manifest.toml"))
    manifest["schema"] == "sequential-informative-oil-v1" || error("unknown manifest schema")
    records = manifest["records"]
    length(records) == 25 || error("expected 25 instances")
    length(unique([r["id"] for r in records])) == 25 || error("duplicate instance ids")
    length(unique([r["seed"] for r in records])) == 25 || error("duplicate seeds")
    length(unique([r["instance_sha256"] for r in records])) == 25 || error("duplicate physical instances")
    for m in 1:5
        group = filter(r -> r["M"] == m, records)
        length(group) == 5 || error("expected five instances at M=$(m)")
        sort([r["seed_id"] for r in group]) == collect(1:5) || error("invalid seed indices at M=$(m)")
    end
    for record in records
        path = joinpath(destination, record["instance_file"])
        isfile(path) || error("missing instance: $(record["id"])")
        sha256_file(path) == record["file_sha256"] || error("file checksum mismatch: $(record["id"])")
        x = load_oil(path)
        instance_hash(x) == record["instance_sha256"] || error("instance hash mismatch: $(record["id"])")
        ntests(x) == record["M"] || error("test count mismatch: $(record["id"])")
        replay = generate_oil(record["M"], record["seed"]; kind=:informative)
        instance_hash(replay) == record["instance_sha256"] || error("generator replay mismatch: $(record["id"])")
        empty_value, full_value = exact_values(x)
        full_value > empty_value || error("F(N) <= F(empty): $(record["id"])")
        string(empty_value) == record["F_empty_exact"] || error("F(empty) mismatch: $(record["id"])")
        string(full_value) == record["F_full_exact"] || error("F(N) mismatch: $(record["id"])")
    end
    println("Validated 25/25 reproducible informative instances; no optimization models were built")
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 1 || error("validate_instances.jl CAMPAIGN_DIRECTORY")
    validate_campaign(abspath(only(ARGS)))
end
