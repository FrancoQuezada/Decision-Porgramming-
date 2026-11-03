"""Write flat CSV records; missing metrics stay empty, never synthetic zeros."""
function write_records(path,records)
    isempty(records) && throw(ArgumentError("no experiment records"))
    cols=unique(vcat([collect(keys(r)) for r in records]...))
    escape_csv(x)= "\""*replace(string(x),'"'=>"\"\"")*"\""
    mkpath(dirname(path))
    open(path,"w") do io
        println(io,join(escape_csv.(cols),","))
        for r in records; println(io,join([escape_csv(get(r,k,"")) for k in cols],",")); end
    end
    path
end

function environment_record()
    Dict{String,Any}("julia"=>string(VERSION),"cpu"=>Sys.cpu_info()[1].model,
        "cpu_threads"=>Sys.CPU_THREADS,"julia_threads"=>Threads.nthreads(),
        "word_size"=>Sys.WORD_SIZE,"memory_bytes"=>Sys.total_memory(),
        "kernel"=>string(Sys.KERNEL),"machine"=>Sys.MACHINE)
end

function source_hash(root)
    paths=String[]
    for folder in ("src","scripts","test")
        for (dir,_,files) in walkdir(joinpath(root,folder)),file in files
            (endswith(file,".jl") || endswith(file,".py")) && push!(paths,relpath(joinpath(dir,file),root))
        end
    end
    append!(paths,["Project.toml","Manifest.toml","external.lock.toml"])
    io=IOBuffer()
    for path in sort(paths)
        write(io,path,'\0',read(joinpath(root,path)),'\0')
    end
    bytes2hex(sha256(take!(io)))
end
export write_records, environment_record, source_hash
