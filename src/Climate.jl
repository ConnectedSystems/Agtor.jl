using CSV, DataFrames, Dates

"""Serves as an interface to climate data"""
mutable struct Climate <: AgComponent

    data::Any
    time_steps::Array
    description::Any
    annual_rainfall::DataFrame

    function Climate(data)
        c = new()
        c.data = data
        c.time_steps = data[!, :Date]
        data[:, :Year] = Dates.year.(data[!, :Date])

        gdf = groupby(data[:, filter(x -> x != :Date, names(data))], :Year)
        not_year_col = filter(x -> x != :Year, names(gdf))
        yearly = aggregate(gdf, sum)

        rain_cols = filter(x -> occursin("rainfall", x), map(string, names(yearly)))
        append!(rain_cols, ["Year"])

        c.annual_rainfall = yearly[:, map(Symbol, rain_cols)]

        stats = [:mean, :std, :min, :q25, :median, :q75, :max, :eltype, :nunique, :nmissing]
        not_year_col = filter(x -> x != :Year, names(yearly))
        c.description = describe(yearly[:, not_year_col], stats...)

        return c
    end
end

function Base.getindex(c::Climate, args...)
    return c.data[args...]
end

# function __getitem__(c::Climate, item)
#     return c.data[item]
# end

# function annual_rainfall(c::Climate, timestep::DateTime)
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
function get_season_range(c::Climate, p_start::DateTime, p_end::DateTime)
    data = c.data
    mask = (data.index >= p_start) && (data.index <= p_end)

    return c.data[mask, :]
end

function ensure_datetime(c::Climate, p_start::String, p_end::String)
    """Converts strings to datetime."""

    s = DateTime(p_start)
    e = DateTime(p_end)

    @assert e > s "Season end date cannot be earlier than start date ($(p_start) < $(p_end) ?)"

    return s, e
end

function get_seasonal_rainfall(c::Climate, season_range::Array{DateTime}, partial_name::String)
    """Retrieve seasonal rainfall by matching column name. 
    Columns names are expected to have 'rainfall' with some identifier.

    Parameters
    ----------
    * season_range : List-like, start and end dates, can be string or datetime object
    * partial_name : str, string to (partially) match column name identifier on

    Example
    ----------
    Where column names are: 'rainfall_field1', 'rainfall_field2', ...

    `get_seasonal_rainfall(['1981-01-01', '1982-06-01'], 'field1')`

    Returns
    --------
    numeric, representing seasonal rainfall
    """
    s, e = ensure_datetime(c, season_range...)
    rain_cols = [c for c in c.data.dtype.names if ("rainfall" in c) && (partial_name in c)]

    subset = get_season_range(c, s, e)[rain_cols]
    return sum(subset)
end

function get_seasonal_et(c::Climate, season_range::Array{DateTime}, partial_name::String)
    """Retrieve seasonal rainfall.

    Parameters
    ----------
    * season_range : List-like, start and end dates, can be string or datetime object
    * partial_name : str, string to (partially) match column name identifier on

    Returns
    --------
    numeric of seasonal rainfall
    """
    s, e = ensure_datetime(c, season_range...)
    et_cols = [c for c in names(c.data) if ("ET" in c) && (partial_name in c)]

    return get_season_range(c, s, e).loc[:, et_cols].sum()[0]
end