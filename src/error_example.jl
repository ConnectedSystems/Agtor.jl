struct Foo{A,B,C}
    a::A
    b::B
    c::C
end

@info Foo(1,2,3)

function create_foo(a, b, c)
    Foo(a, b, c)
end

function create_foo(a, b, c, d::String)
    Foo(a[:c], b, c)
end

create_foo(Dict(:a=>100), 10, 1, "test")