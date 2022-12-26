push!(LOAD_PATH, "../src/")

using Documenter, Agtor


makedocs(
    sitename="Agtor.jl - a programmatic farm modeling framework",
    modules = [Agtor],
    pages=[
        "index.md",
        "getting_started.md",
    ]
)
