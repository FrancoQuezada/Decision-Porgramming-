using TOML

root=dirname(@__DIR__)
lock=TOML.parsefile(joinpath(root,"external.lock.toml"))
for key in sort(collect(keys(lock)))
    ref=lock[key]; dest=joinpath(root,ref["path"])
    if !isdir(dest)
        run(`git clone $(ref["url"]) $dest`)
        run(`git -C $dest checkout --detach $(ref["commit"])`)
    end
    sha=readchomp(`git -C $dest rev-parse HEAD`)
    sha==ref["commit"] || error("$dest has a different commit: $sha")
    isempty(readchomp(`git -C $dest status --porcelain`)) || error("reference has local changes: $dest")
    println(key,": ",sha)
end
