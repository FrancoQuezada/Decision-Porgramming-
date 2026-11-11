"""Testing rows use (stage, previous reports); 0 denotes N/A, 1:R a real report."""
const SequentialOilKey = Tuple{Int,Tuple}

struct PartialSequentialOilPolicy
    actions::Dict{SequentialOilKey,Bool}
    function PartialSequentialOilPolicy(actions::AbstractDict=Dict{SequentialOilKey,Bool}())
        all(a -> a isa Integer && a in (0,1), values(actions)) ||
            throw(ArgumentError("testing actions must be 0 or 1"))
        new(Dict{SequentialOilKey,Bool}(actions))
    end
end

struct SequentialOilPolicy
    testing::Dict{SequentialOilKey,Bool}
    drill::Dict{Tuple,Bool} # full report histories, including N/A
end

function sequential_policy_rows(x::OilInstance; max_rows=100_000)
    nr=size(x.reports,3)
    count=sum((big(nr+1)^(i-1) for i in 1:ntests(x)); init=big(0))
    count <= max_rows || throw(ArgumentError("sequential policy row size guard"))
    rows=SequentialOilKey[]
    for i in 1:ntests(x), h in Iterators.product(ntuple(_ -> 0:nr,i-1)...)
        push!(rows,(i,h))
    end
    rows
end

function validate_sequential_testing(x::OilInstance, actions; complete=false)
    m=ntests(x); nr=size(x.reports,3)
    for ((i,h),a) in actions
        1 <= i <= m && length(h)==i-1 && all(r -> r isa Integer && 0 <= r <= nr,h) ||
            throw(ArgumentError("invalid sequential testing history: $((i,h))"))
        a isa Integer && a in (0,1) || throw(ArgumentError("invalid testing action"))
    end
    count=sum((big(nr+1)^(i-1) for i in 1:m); init=big(0))
    complete && length(actions)!=count && throw(ArgumentError("incomplete sequential testing policy"))
    true
end

"""Complete every row, including unreachable rows, respecting every fixing."""
function complete_sequential_testing(x::OilInstance, p::PartialSequentialOilPolicy;
        max_rows=100_000, rows=nothing)
    validate_sequential_testing(x,p.actions)
    Dict{SequentialOilKey,Bool}(key=>get(p.actions,key,false)
        for key in (isnothing(rows) ? sequential_policy_rows(x;max_rows) : rows))
end

"""Rows that can still be reached under at least one completion of `p`.

This is structural reachability: `0` is possible only after `skip`, while a real
report is possible only after `test`. Zero-probability chance branches are left
in place, so the reduction never depends on numerical probability tests.
"""
function reachable_sequential_rows(x::OilInstance, p::PartialSequentialOilPolicy)
    validate_sequential_testing(x,p.actions)
    nr=size(x.reports,3); histories=Tuple[()]; rows=SequentialOilKey[]
    for i in 1:ntests(x)
        next=Tuple[]
        for h in histories
            key=(i,h); push!(rows,key)
            actions=haskey(p.actions,key) ? (p.actions[key],) : (false,true)
            false in actions && push!(next,(h...,0))
            if true in actions
                for r in 1:nr; push!(next,(h...,r)); end
            end
        end
        histories=next
    end
    rows
end

"""Drop fixings that cannot affect any physical trajectory under the fixings."""
function canonical_sequential_policy(x::OilInstance, p::PartialSequentialOilPolicy)
    reachable=Set(reachable_sequential_rows(x,p))
    PartialSequentialOilPolicy(Dict(key=>action for (key,action) in p.actions if key in reachable))
end

"""Hashable canonical partial-policy representation in global row order."""
function canonical_sequential_key(x::OilInstance, p::PartialSequentialOilPolicy)
    q=canonical_sequential_policy(x,p)
    Tuple((key[1],key[2],q.actions[key]) for key in reachable_sequential_rows(x,q)
        if haskey(q.actions,key))
end

"""Physical testing-policy key; off-trajectory decisions are deliberately absent."""
function physical_sequential_key(x::OilInstance, testing::AbstractDict)
    validate_sequential_testing(x,testing;complete=true)
    nr=size(x.reports,3); histories=Tuple[()]; key=Tuple{Int,Tuple,Bool}[]
    for i in 1:ntests(x)
        next=Tuple[]
        for h in histories
            action=testing[(i,h)]; push!(key,(i,h,action))
            if action
                for r in 1:nr; push!(next,(h...,r)); end
            else
                push!(next,(h...,0))
            end
        end
        histories=next
    end
    Tuple(key)
end

export SequentialOilKey, SequentialOilPolicy, PartialSequentialOilPolicy
export sequential_policy_rows, complete_sequential_testing, reachable_sequential_rows
export canonical_sequential_policy, canonical_sequential_key, physical_sequential_key
