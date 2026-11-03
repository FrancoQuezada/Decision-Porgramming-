using Pkg,TOML
root=dirname(@__DIR__)
envdir=joinpath(root,"environments","cplex")
mkpath(envdir)
project=TOML.parsefile(joinpath(root,"Project.toml"))
deps=copy(project["deps"])
deps["DecisionProgrammingAlgorithms"]=project["uuid"]
deps["CPLEX"]="a076750e-1247-5638-91d2-ce28b192dca0"
compat=copy(project["compat"]);compat["CPLEX"]="=1.1.1"
open(io->TOML.print(io,Dict("deps"=>deps,"compat"=>compat);sorted=true),joinpath(envdir,"Project.toml"),"w")
# Seed resolution from the research lock without changing the root environment.
isfile(joinpath(envdir,"Manifest.toml")) || cp(joinpath(root,"Manifest.toml"),joinpath(envdir,"Manifest.toml"))
if isempty(get(ENV,"CPLEX_STUDIO_BINARIES",""))
    candidates=String[]
    for base in ("/opt/ibm/ILOG","/opt/IBM/ILOG")
        isdir(base) || continue
        for folder in readdir(base;join=true)
            path=joinpath(folder,"cplex","bin","x86-64_linux")
            isdir(path) && any(startswith(f,"libcplex") && endswith(f,".so") for f in readdir(path)) && push!(candidates,path)
        end
    end
    isempty(candidates) && error("Set CPLEX_STUDIO_BINARIES to the installed CPLEX library directory")
    ENV["CPLEX_STUDIO_BINARIES"]=last(sort(candidates))
end
println("CPLEX_STUDIO_BINARIES=",ENV["CPLEX_STUDIO_BINARIES"])
Pkg.activate(envdir)
cd(envdir) do
    Pkg.develop(PackageSpec(path="../.."))
end
Pkg.add(PackageSpec(name="CPLEX",version="1.1.1"))
Pkg.pin("CPLEX")
Pkg.build("CPLEX")
Pkg.precompile()
