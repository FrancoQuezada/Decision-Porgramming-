"""Exact content remains the equality criterion; a stored hash only accelerates lookup."""
struct ModelIdentity
    content::Tuple
    digest::UInt
    ModelIdentity(content::Tuple)=new(content,hash(content))
end
Base.isequal(a::ModelIdentity,b::ModelIdentity)=isequal(a.content,b.content)
Base.:(==)(a::ModelIdentity,b::ModelIdentity)=isequal(a,b)
Base.hash(a::ModelIdentity,h::UInt)=hash(a.digest,h)

function model_content(id::InfluenceDiagramInstance)
    nodes=Tuple(node isa ChanceNode ?
        (:chance,node.name,node.states,Tuple(node.parents),size(node.kernel),Tuple(node.kernel)) :
        (:decision,node.name,node.states,Tuple(node.information)) for node in id.nodes)
    utilities=Tuple((Tuple(u.scope),size(u.values),Tuple(u.values)) for u in id.utilities)
    (:unconstrained_expected_utility_v1,nodes,utilities)
end
model_identity(plan::StructuredPlan)=ModelIdentity(model_content(plan.relaxation.original))
relaxation_identity(plan::StructuredPlan)=Tuple((i,Tuple(d.information)) for (i,d) in enumerate(plan.relaxation.relaxed.nodes) if d isa DecisionNode)

struct ContextKey
    instance::ModelIdentity
    relaxation::Tuple
    stage::Int
    separator::Tuple
    fixings::Tuple
end
Base.isequal(a::ContextKey,b::ContextKey)=isequal(a.instance,b.instance) &&
    isequal(a.relaxation,b.relaxation) && a.stage==b.stage &&
    isequal(a.separator,b.separator) && isequal(a.fixings,b.fixings)
Base.:(==)(a::ContextKey,b::ContextKey)=isequal(a,b)
Base.hash(k::ContextKey,h::UInt)=hash((k.instance,k.relaxation,k.stage,k.separator,k.fixings),h)

function residual_fixings(rows,k,assignment)
    residual=Tuple{Int,Tuple,Int}[]
    for row in rows
        row.decision<k && continue
        all(v>=k || assignment[v]==row.history[j] for (j,v) in enumerate(row.information)) || continue
        remaining=Tuple(row.history[j] for (j,v) in enumerate(row.information) if v>=k)
        push!(residual,(row.decision,remaining,row.action))
    end
    Tuple(sort!(residual))
end
function make_context_key(plan,identity,information,rows,k,assignment)
    ContextKey(identity,information,k,Tuple(assignment[j] for j in plan.separators[k]),
        residual_fixings(rows,k,assignment))
end

"""Diagnostic key for a causal prefix; does not insert or count a cache access."""
function context_key(o::StructuredOracle,p::PartialPolicy,k::Int,prefix::Tuple)
    n=length(o.plan.relaxation.original.nodes)
    1<=k<=n && length(prefix)==k-1 || throw(ArgumentError("prefix length/stage"))
    all(1<=a<=o.plan.relaxation.original.nodes[j].states for (j,a) in enumerate(prefix)) || throw(ArgumentError("prefix states"))
    assignment=vcat(collect(prefix),zeros(Int,n-k+1))
    make_context_key(o.plan,model_identity(o.plan),relaxation_identity(o.plan),fixed_rows(o.plan,p),k,assignment)
end
export ModelIdentity, ContextKey, context_key
