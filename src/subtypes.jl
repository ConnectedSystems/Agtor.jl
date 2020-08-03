using DataFrames

@info subtypes(DataFrame)

function get_subtypes()
    return subtypes(DataFrame)
end

@info get_subtypes()