using JuMP, GLPK, Test

"""
    example_basic([; verbose = true])
Formulate and solve a simple LP:
    max 5x + 3y
     st 1x + 5y <= 3
         0 <= x <= 2
         0 <= y <= 30
If `verbose = true`, print the model and the solution.
"""
function example_basic(; verbose = true)

    for i = 1:13000

        model = Model(with_optimizer(GLPK.Optimizer))

        @variable(model, 0 <= x <= 2)
        @variable(model, 0 <= y <= 30)

        @objective(model, Max, 5x + 3y)
        @constraint(model, 1x + 5y <= 3.0)

        if verbose
            print(model)
        end

        JuMP.optimize!(model)

        obj_value = JuMP.objective_value(model)
        x_value = JuMP.value(x)
        y_value = JuMP.value(y)
    end

    if verbose
        println("Objective value: ", obj_value)
        println("x = ", x_value)
        println("y = ", y_value)
    end

    # @test obj_value ≈ 10.6
    # @test x_value ≈ 2
    # @test y_value ≈ 0.2
end

example_basic(verbose = false)