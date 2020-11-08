using DataFrames, Dates


"""Serves as an interface to climate data"""
mutable struct Climate <: AgComponent

    data::Any
    time_steps::Array
    description::Any
    annual_rainfall::DataFrame

    function Climate(data::DataFrame)
        c = new()
        c.data = data
        c.time_steps = data[!, :Date]
        data[:, :Year] = Dates.year.(c.time_steps)

        gdf = groupby(data[:, filter(x -> x != :Date, propertynames(data))], :Year)

        not_year_col::Array{Symbol,1} = collect(filter(x -> x != :Year, propertynames(gdf)))
        yearly = combine(gdf, names(gdf) .=> sum)

        rain_cols::Array{Symbol,1} = filter(x -> occursin("rainfall", string(x)), propertynames(yearly))
        push!(rain_cols, :Year)

        c.annual_rainfall = yearly[:, rain_cols]

        stats::Array{Symbol,1} = [:mean, :std, :min, :q25, :median, :q75, :max, :eltype, :nunique, :nmissing]
        not_year_col = filter(x -> x != :Year, propertynames(yearly))

        c.description = describe(yearly[:, not_year_col], stats...)

        return c
    end
end

function Base.getindex(c::Climate, args...)::DataFrame
    return c.data[args...]
end

# function __getitem__(c::Climate, item)
#     return c.data[item]
# end

# function annual_rainfall(c::Climate, timestep::Date)
#     """
#     Calculate the total amount of rainfall that occured in a year, given in the timestep

#     Parameters
#     ----------
#     * timestep : datetime or int, indicating year in terms of time step.
#     """
#     year = timestep if type(timestep) == int else timestep.year
#     data = c.data

#     year_data = data[data.index.year == year]
#     yearly_rainfall = year_data.sum()

#     return yearly_rainfall['rainfall']
# end

# function annual_rainfall(c::Climate, timestep::Int64)
#     """
#     Calculate the total amount of rainfall that occured in a year, by index position.

#     Parameters
#     ----------
#     * timestep : Indicating year in terms of index position.
#     """
#     data = c.data

#     year_data = data[data.index.year == timestep]
#     yearly_rainfall = sum(year_data)

#     return yearly_rainfall['rainfall']
# end

"""Gets climate data for season range.

Parameters
----------
* p_start : datetime, start of range in Y-m-d format, inclusive.
* p_end : datetime, end of range in Y-m-d format, inclusive.
"""
function get_season_range(c::Climate, p_start::Date, p_end::Date)::DataFrame
    dates::Array{Date,1} = c.time_steps::Array{Date,1}
    mask::BitArray{1} = (p_start .<= dates .<= p_end)::BitArray{1}
    return c.data[mask, :]
end


"""Converts strings to datetime."""
function ensure_date(c::Climate, p_start::String, p_end::String)::Tuple
    s::Date = Date(p_start)
    e::Date = Date(p_end)

    @assert e > s "Season end date cannot be earlier than start date ($(p_start) < $(p_end) ?)"

    return s, e
end


"""Retrieve seasonal rainfall by matching column name. 
Columns names are expected to have 'rainfall' with some identifier.

Parameters
----------
* season_range : List-like, start and end dates, can be string or datetime object
* partial_name : str, string to (partially) match column name identifier on

Example
----------
Where column names are: 'rainfall_field1', 'rainfall_field2', ...

`get_seasonal_rainfall(c, ['1981-01-01', '1982-06-01'], 'field1')`

Returns
--------
numeric, representing seasonal rainfall
"""
function get_seasonal_rainfall(c::Climate, season_range::Array{Date}, partial_name::String)::Float64
    s::Date, e::Date = season_range
    subset::DataFrame = get_season_range(c, s, e)[!, Regex("rainfall")][!, Regex(partial_name)]
    return sum.(eachcol(subset))[1]
end


"""Retrieve seasonal evapotranspiration.

Parameters
----------
* season_range : List-like, start and end dates, can be string or datetime object
* partial_name : str, string to (partially) match column name identifier on

Returns
--------
numeric of seasonal rainfall
"""
function get_seasonal_et(c::Climate, season_range::Array{Date}, partial_name::String)::DataFrame
    s::Date, e::Date = season_range
    subset::DataFrame = get_season_range(c, s, e)[!, Regex("ET")][!, Regex(partial_name)]
    return sum.(eachcol(subset))[1]
end
