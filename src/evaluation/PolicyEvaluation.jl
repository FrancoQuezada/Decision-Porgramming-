struct EnumerationEvaluator <: AbstractPolicyEvaluator end
struct VariableEliminationEvaluator <: AbstractPolicyEvaluator
    order::Vector{Int}
end

function evaluate_policy(id::InfluenceDiagramInstance,p::Policy,::EnumerationEvaluator=EnumerationEvaluator())
    validate_policy(id,p)
    assignment=zeros(Int,length(id.nodes))
    function visit(i,prob)
        if i>length(id.nodes)
            return prob*sum((u.values[assignment[u.scope]...] for u in id.utilities); init=zero(Exact))
        end
        n=id.nodes[i]
        if n isa DecisionNode
            assignment[i]=p.actions[(i,Tuple(assignment[n.information]))]
            return visit(i+1,prob)
        end
        val=zero(Exact)
        for s in 1:n.states
            assignment[i]=s
            q=n.kernel[assignment[n.parents]...,s]
            q==0 || (val+=visit(i+1,prob*q))
        end
        val
    end
    visit(1,one(Exact))
end

struct ExactFactor
    scope::Vector{Int}
    values::Array{Exact}
end
function multiply_factors(id,factors)
    scope=sort(unique(vcat((f.scope for f in factors)...)))
    vals=fill(one(Exact),Tuple(id.nodes[j].states for j in scope))
    for index in CartesianIndices(vals)
        assignment=Tuple(index)
        for f in factors
            localstate=Tuple(assignment[findfirst(==(j),scope)] for j in f.scope)
            vals[index]*=f.values[localstate...]
        end
    end
    ExactFactor(scope,vals)
end
function sum_out(f::ExactFactor,j)
    dim=findfirst(==(j),f.scope)
    isnothing(dim) && return f
    ExactFactor(filter(!=(j),f.scope),dropdims(sum(f.values; dims=dim); dims=dim))
end
function evaluate_policy(id::InfluenceDiagramInstance,p::Policy,e::VariableEliminationEvaluator)
    validate_policy(id,p)
    sort(e.order)==collect(eachindex(id.nodes)) || throw(ArgumentError("elimination order must be a permutation"))
    base=ExactFactor[]
    for (i,n) in enumerate(id.nodes)
        if n isa ChanceNode
            push!(base,ExactFactor(vcat(n.parents,i),n.kernel))
        else
            vals=fill(zero(Exact),Tuple(vcat([id.nodes[j].states for j in n.information],n.states)))
            for h in Iterators.product((1:id.nodes[j].states for j in n.information)...)
                vals[h...,p.actions[(i,h)]]=1
            end
            push!(base,ExactFactor(vcat(n.information,i),vals))
        end
    end
    total=zero(Exact)
    for u in id.utilities
        fs=vcat(base,[ExactFactor(u.scope,u.values)])
        for j in e.order
            bucket=[f for f in fs if j in f.scope]
            isempty(bucket) && continue
            fs=[f for f in fs if !(j in f.scope)]
            push!(fs,sum_out(multiply_factors(id,bucket),j))
        end
        total+=multiply_factors(id,fs).values[]
    end
    total
end

function enumerate_policies(id::InfluenceDiagramInstance,p::PartialPolicy=PartialPolicy();
        evaluator=EnumerationEvaluator(),max_policies=1_000_000)
    best=nothing; policy=nothing; count=0
    foreach_policy(id,p; max_policies) do z
        v=evaluate_policy(id,z,evaluator); count+=1
        if isnothing(best) || v>best; best=v; policy=z; end
    end
    (value=best,policy=policy,evaluations=count)
end
export EnumerationEvaluator, VariableEliminationEvaluator, enumerate_policies
