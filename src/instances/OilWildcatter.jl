const Exact = Rational{BigInt}
exact(x::Real) = isfinite(x) ? convert(Exact, x) : throw(ArgumentError("nonfinite input"))

function probability_vector(v)
    q = exact.(v)
    all(>=(0), q) || throw(ArgumentError("negative probability"))
    abs(Float64(sum(q)) - 1) <= 1e-12 || throw(ArgumentError("probabilities must sum to one"))
    q ./ sum(q) # exact normalization of the supplied numerical distribution
end

"""Ex-ante passive tests, independent conditional on S. No-drill utility is zero.

Probabilities are converted to exact rationals and normalized exactly per row.
This finite-input semantics permits certified pruning without floating-point tolerances.
"""
struct OilInstance
    prior::Vector{Exact}
    geology::Matrix{Exact}       # O × S
    reports::Array{Exact,3}      # test × S × report (N/A is implicit)
    payoff::Vector{Exact}        # reward minus drilling cost, excluding test costs
    costs::Vector{Exact}
    metadata::Dict{String,Any}
    function OilInstance(prior, geology, reports, payoff, costs; metadata=Dict{String,Any}())
        no, ns = size(geology)
        m, rs, nr = size(reports)
        no > 0 && ns > 0 && nr > 0 || throw(ArgumentError("empty state space"))
        length(prior) == no == length(payoff) || throw(DimensionMismatch("oil states"))
        rs == ns && length(costs) == m || throw(DimensionMismatch("reports/costs"))
        0 <= m <= 60 || throw(ArgumentError("at most 60 tests supported by masks"))
        p = probability_vector(prior)
        g = Matrix{Exact}(undef, no, ns)
        r = Array{Exact}(undef, m, ns, nr)
        for o in 1:no; g[o,:] = probability_vector(geology[o,:]); end
        for i in 1:m, s in 1:ns; r[i,s,:] = probability_vector(reports[i,s,:]); end
        c = exact.(costs)
        all(>=(0), c) || throw(ArgumentError("test costs must be nonnegative"))
        new(p, g, r, exact.(payoff), c, Dict{String,Any}(metadata))
    end
end

ntests(x::OilInstance) = length(x.costs)
full_mask(x::OilInstance) = (UInt64(1) << ntests(x)) - UInt64(1)
function check_mask(x::OilInstance, mask::UInt64)
    mask & ~full_mask(x) == 0 || throw(ArgumentError("mask outside test set"))
    mask
end
selected_tests(x::OilInstance, mask::UInt64) = [i for i in 1:ntests(x) if mask & (UInt64(1) << (i-1)) != 0]
test_cost(x::OilInstance, mask::UInt64) = sum((x.costs[i] for i in selected_tests(x, check_mask(x, mask))); init=zero(Exact))
outcomes(n::Int, k::Int) = Iterators.product(ntuple(_ -> 1:n, k)...)

"""Independent generator v1. Classes preserve the paper's conditional-independence DAG.

`:redundant` uses deterministic duplicate reports from a common latent state.
No arbitrary report-to-report dependence is introduced.
"""
function generate_oil(m::Int, seed::Int; states::Int=3, report_states::Int=states,
        kind::Symbol=:informative, accuracy=0.8, prior=nothing, geology=nothing,
        report_kernel=nothing, costs=nothing, drilling_cost=100.0, rewards=nothing)
    states >= 2 && report_states >= 2 || throw(ArgumentError("at least two states required"))
    0 <= m <= 60 || throw(ArgumentError("test count"))
    kind in (:informative, :uninformative, :heterogeneous, :redundant) || throw(ArgumentError("unknown class"))
    acc = accuracy isa Real ? fill(Float64(accuracy), m) : Float64.(accuracy)
    length(acc) == m && all(a -> 0 <= a <= 1, acc) || throw(ArgumentError("accuracy"))
    rng = Xoshiro(seed)
    normrow(v) = v ./ sum(v)
    p = isnothing(prior) ? normrow(0.5 .+ rand(rng, states)) : prior
    g = zeros(states, states)
    for o in 1:states
        row = 0.1 .+ rand(rng, states)
        row[o] += 8
        g[o,:] = normrow(row)
    end
    !isnothing(geology) && (g = geology)
    r = zeros(m, states, report_states)
    for i in 1:m
        noise = normrow(0.5 .+ rand(rng, report_states))
        for s in 1:states
            if kind == :redundant
                r[i,s,1 + mod(s-1, report_states)] = 1
            elseif kind == :uninformative
                r[i,s,:] = noise
            else
                r[i,s,:] = (1-acc[i]) .* noise
                r[i,s,1 + mod(s-1, report_states)] += acc[i]
            end
        end
    end
    !isnothing(report_kernel) && (r = report_kernel)
    c = isnothing(costs) ? (kind == :heterogeneous ? 0.1 .+ 25 .* rand(rng,m) : 1 .+ 8 .* rand(rng,m)) : costs
    rew = isnothing(rewards) ? collect(range(0.0, 240.0; length=states)) : rewards
    OilInstance(p, g, r, rew .- drilling_cost, c;
        metadata=Dict("generator"=>"independent-v1", "seed"=>seed, "kind"=>string(kind),
            "accuracy"=>acc, "drilling_cost"=>drilling_cost, "report_states"=>report_states))
end

function oil_payload(x::OilInstance)
    Dict("format"=>"oil-exact-v1", "prior"=>string.(x.prior),
        "geology"=>[string.(x.geology[o,:]) for o in axes(x.geology,1)],
        "reports"=>[[string.(x.reports[i,s,:]) for s in axes(x.reports,2)] for i in axes(x.reports,1)],
        "report_states"=>size(x.reports,3), "payoff"=>string.(x.payoff),
        "costs"=>string.(x.costs), "metadata"=>x.metadata)
end
function save_oil(path, x::OilInstance)
    mkpath(dirname(path))
    open(io -> TOML.print(io, oil_payload(x); sorted=true), path, "w")
    path
end
function load_oil(path)
    d = TOML.parsefile(path)
    d["format"] == "oil-exact-v1" || throw(ArgumentError("instance format"))
    q(s) = parse(BigInt, split(s,"//")[1]) // parse(BigInt, split(s,"//")[2])
    p, c = q.(d["prior"]), q.(d["costs"])
    g = reduce(vcat, permutedims.(q.(row) for row in d["geology"]))
    r = Array{Exact}(undef,length(c),size(g,2),d["report_states"])
    for i in eachindex(c), s in axes(g,2); r[i,s,:] = q.(d["reports"][i][s]); end
    OilInstance(p,g,r,q.(d["payoff"]),c; metadata=d["metadata"])
end
function instance_hash(x::OilInstance)
    io = IOBuffer(); TOML.print(io,oil_payload(x); sorted=true)
    bytes2hex(sha256(take!(io)))
end

export Exact, OilInstance, generate_oil, ntests, full_mask, selected_tests, test_cost
export save_oil, load_oil, instance_hash
