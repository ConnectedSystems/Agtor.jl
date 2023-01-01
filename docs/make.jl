push!(LOAD_PATH, "../src/")

using Documenter, Agtor


makedocs(
    format=Documenter.HTML(
        prettyurls=get(ENV, "CI", nothing) == "true",
        sidebar_sitename=true
    ),
    sitename="Agtor.jl",
    modules = [Agtor],
    pages=[
        "index.md",
        "specs.md",
        "getting_started.md",
        "API.md",
    ]
)


