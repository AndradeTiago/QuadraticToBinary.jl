const MOI = MathOptInterface
const MOIU = MOI.Utilities

const VI = MOI.VariableIndex
const CI = MOI.ConstraintIndex

# same as MOI except for quad stuff
MOIU.@model(NonQuadraticModel,
       (MOI.ZeroOne, MOI.Integer),
       (MOI.EqualTo, MOI.GreaterThan, MOI.LessThan, MOI.Interval,
        MOI.Semicontinuous, MOI.Semiinteger),
       (MOI.Reals, MOI.Zeros, MOI.Nonnegatives, MOI.Nonpositives,
        MOI.Complements, MOI.NormInfinityCone, MOI.NormOneCone,
        MOI.SecondOrderCone, MOI.RotatedSecondOrderCone,
        MOI.GeometricMeanCone, MOI.ExponentialCone, MOI.DualExponentialCone,
        MOI.RelativeEntropyCone, MOI.NormSpectralCone, MOI.NormNuclearCone,
        MOI.PositiveSemidefiniteConeTriangle, MOI.PositiveSemidefiniteConeSquare,
        MOI.RootDetConeTriangle, MOI.RootDetConeSquare, MOI.LogDetConeTriangle,
        MOI.LogDetConeSquare),
       (MOI.PowerCone, MOI.DualPowerCone, MOI.SOS1, MOI.SOS2),
       (),
       (MOI.ScalarAffineFunction,),
       (MOI.VectorOfVariables,),
       (MOI.VectorAffineFunction,))

MOIU.@model(PureQuadraticModel,
       (MOI.ZeroOne, MOI.Integer),
       (MOI.EqualTo, MOI.GreaterThan, MOI.LessThan, MOI.Interval,
        MOI.Semicontinuous, MOI.Semiinteger),
       (MOI.Reals, MOI.Zeros, MOI.Nonnegatives, MOI.Nonpositives,
        MOI.Complements, MOI.NormInfinityCone, MOI.NormOneCone,
        MOI.SecondOrderCone, MOI.RotatedSecondOrderCone,
        MOI.GeometricMeanCone, MOI.ExponentialCone, MOI.DualExponentialCone,
        MOI.RelativeEntropyCone, MOI.NormSpectralCone, MOI.NormNuclearCone,
        MOI.PositiveSemidefiniteConeTriangle, MOI.PositiveSemidefiniteConeSquare,
        MOI.RootDetConeTriangle, MOI.RootDetConeSquare, MOI.LogDetConeTriangle,
        MOI.LogDetConeSquare),
       (MOI.PowerCone, MOI.DualPowerCone, MOI.SOS1, MOI.SOS2,),
       (),
       (MOI.ScalarQuadraticFunction,),
       (),
       (MOI.VectorQuadraticFunction,))

const SCALAR_SETS = Union{
    MOI.GreaterThan{Float64},
    MOI.LessThan{Float64},
    MOI.EqualTo{Float64},
    MOI.Interval{Float64},
}

const SCALAR_TYPES = Union{
    MOI.ZeroOne,
    MOI.Integer,
}

@enum(
    VariableType,
    CONTINUOUS,
    BINARY,
    INTEGER,
    SEMIINTEGER,
    SEMICONTINUOUS,
)

@enum(
    BoundType,
    NONE,
    LESS_THAN,
    GREATER_THAN,
    LESS_AND_GREATER_THAN,
    INTERVAL,
    EQUAL_TO,
)

mutable struct VariableInfo
    upper::Float64
    lower::Float64
    bound::BoundType
    type::VariableType
    initial_precision::Float64
    # target_precision::Float64
    # start::Union{Float64, Nothing}
    function VariableInfo()
        return new(
            +Inf,
            -Inf,
            NONE,
            CONTINUOUS,
            NaN
            )
    end
end

# Supported Functions
const SF = Union{MOI.SingleVariable, 
                 MOI.ScalarAffineFunction{Float64}, 
                 MOI.VectorOfVariables, 
                 MOI.VectorAffineFunction{Float64}}

# Supported Sets
const SS = Union{MOI.EqualTo{Float64}, MOI.GreaterThan{Float64}, MOI.LessThan{Float64}, 
                 MOI.Zeros, MOI.Nonnegatives, MOI.Nonpositives, 
                 MOI.SecondOrderCone, MOI.RotatedSecondOrderCone,
                 MOI.ExponentialCone, MOI.DualExponentialCone,
                 MOI.PowerCone, MOI.DualPowerCone,
                 MOI.PositiveSemidefiniteConeTriangle}

const QuadraticFunction{T} = Union{
    MOI.ScalarQuadraticFunction{T},
    MOI.VectorQuadraticFunction{T}
}

mutable struct Optimizer{T, OT <: MOI.ModelLike} <: MOI.AbstractOptimizer
    # model to be solved
    optimizer::OT # integer programming solver

    global_initial_precision::Float64
    # global_target_precision::Float64

    # quadratic solver, usually NLP (has to accpet other conic constraints)

    # quadratic constraint cache
    # quadratic_cache::PureQuadraticModel{T}

    # map between quadratic cache and optimizer data
    # goes from ci{quad,set} to ci{aff,set}
    quad_obj::Union{Nothing, MOI.ScalarQuadraticFunction{T}}
    ci_to_quad_scalar::Dict{CI, MOI.ScalarQuadraticFunction{T}}
    ci_to_quad_vector::Dict{CI, MOI.VectorQuadraticFunction{T}}

    original_variables::Dict{VI, VariableInfo}
    ci_to_var::Dict{CI, VI}

    pair_to_var::Dict{Tuple{VI,VI}, VI} # wij variable

    function Optimizer{T}(optimizer::OT) where {T, OT <: MOI.ModelLike}
        # TODO optimizer must support binary, and affine in less and greater
        return new{T, OT}(
            optimizer,
            1e-4,
            nothing,
            Dict{CI, MOI.ScalarQuadraticFunction{T}}(),
            Dict{CI, MOI.VectorQuadraticFunction{T}}(),
            Dict{VI, VariableInfo}(),
            Dict{CI, VI}(),
            Dict{Tuple{VI,VI}, VI}()
            )
    end
end

function MOI.is_empty(model::Optimizer)
    return MOI.is_empty(model.optimizer) &&
    model.quad_obj === nothing &&
    isempty(model.ci_to_quad_scalar) &&
    isempty(model.ci_to_quad_vector) &&
    isempty(model.original_variables) &&
    isempty(model.ci_to_var) &&
    isempty(model.pair_to_var)
end

function MOI.empty!(model::Optimizer{T}) where T
    MOI.empty!(model.optimizer)
    model.quad_obj = nothing
    model.ci_to_quad_scalar = Dict{CI, MOI.ScalarQuadraticFunction{T}}()
    model.ci_to_quad_vector = Dict{CI, MOI.VectorQuadraticFunction{T}}()
    model.original_variables = Dict{VI, VariableInfo}()
    model.ci_to_var = Dict{CI, VI}()
    model.pair_to_var = Dict{Tuple{VI,VI}, VI}()
    return
end

function store_quadratic!(model::Optimizer, ci::CI{F,S}, f::F
    ) where {S, F<:MOI.ScalarQuadraticFunction{T}} where T
    model.ci_to_quad_scalar[ci] = f
    return
end
function store_quadratic!(model::Optimizer, ci::CI{F,S}, f::F
    ) where {S, F<:MOI.VectorQuadraticFunction{T}} where T
    model.ci_to_quad_vector[ci] = f
    return
end
function get_quadratic(model::Optimizer, ci::CI{F,S}
    ) where {S, F<:MOI.ScalarQuadraticFunction{T}} where T
    return model.ci_to_quad_scalar[ci]
end
function get_quadratic(model::Optimizer, ci::CI{F,S}
    ) where {S, F<:MOI.VectorQuadraticFunction{T}} where T
    return model.ci_to_quad_vector[ci]
end
function delete_quadratic!(model::Optimizer, ci::CI{F,S}
    ) where {S, F<:MOI.ScalarQuadraticFunction{T}} where T
    delete!(model.ci_to_quad_scalar, ci)
end
function delete_quadratic!(model::Optimizer, ci::CI{F,S}
    ) where {S, F<:MOI.VectorQuadraticFunction{T}} where T
    delete!(model.ci_to_quad_vector, ci)
end
function get_indices(model::Optimizer, ::Type{F}
    ) where {F<:MOI.ScalarQuadraticFunction{T}} where T
    keys(model.ci_to_quad_scalar)
end
function get_indices(model::Optimizer, ::Type{F}
    ) where {F<:MOI.VectorQuadraticFunction{T}} where T
    keys(model.ci_to_quad_vector)
end

function MOI.supports(model::Optimizer,
    attr::Union{MOI.ObjectiveSense,
            MOI.ObjectiveFunction{MOI.SingleVariable},
            MOI.ObjectiveFunction{MOI.ScalarAffineFunction{T}},
            }) where T
    return MOI.supports(model.optimizer, attr)
end
function MOI.supports(model::Optimizer,
    ::MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{T}}) where T
    # this is what reformulation will add to optimizer
    return MOI.supports(model.optimizer,
        MOI.ObjectiveFunction{MOI.ScalarAffineFunction{T}}())
end

function MOI.supports_constraint(model::Optimizer,
    F::Type{<:MOI.AbstractFunction}, S::Type{<:MOI.AbstractSet})
    return MOI.supports_constraint(model.optimizer, F, S)
end
function MOI.supports_constraint(model::Optimizer,
    F::Type{<:QuadraticFunction{T}}, S::Type{<:MOI.AbstractSet}) where T
    return MOI.supports_constraint(model.optimizer, affine_type(F), S)
end
affine_type(::MOI.ScalarQuadraticFunction{T}) where T = MOI.ScalarAffineFunction{T}
affine_type(::MOI.VectorQuadraticFunction{T}) where T = MOI.VectorAffineFunction{T}
affine_type(::Type{MOI.ScalarQuadraticFunction{T}}) where T = MOI.ScalarAffineFunction{T}
affine_type(::Type{MOI.VectorQuadraticFunction{T}}) where T = MOI.VectorAffineFunction{T}
quadratic_type(::Type{MOI.ScalarAffineFunction{T}}) where T = MOI.ScalarQuadraticFunction{T}
quadratic_type(::Type{MOI.VectorAffineFunction{T}}) where T = MOI.VectorQuadraticFunction{T}


function MOI.get(model::Optimizer, ::MOI.SolverName)
    return "Binary reformulation of quadratic model with solver " *
        MOI.get(model.optimizer, MOI.SolverName()) * " attached"
end

function MOI.supports_add_constrained_variables(
    model::Optimizer, ::Type{S}) where S
    return MOI.supports_add_constrained_variables(model.optimizer, S)
end

# function MOI.set(model::Optimizer, param::MOI.RawParameter, value)
#     # if in a subset of the q2b save it
#     # otherwise pass it forward
# end

# function MOI.get(model::Optimizer, param::MOI.RawParameter)
# end

MOI.Utilities.supports_default_copy_to(::Optimizer, ::Bool) = false

function MOI.copy_to(dest::Optimizer, src::MOI.ModelLike; kwargs...)
    return MOI.Utilities.automatic_copy_to(dest, src; kwargs...)
end


##
## variable
##

function MOI.add_variable(model::Optimizer)
    v = MOI.add_variable(model.optimizer)
    model.original_variables[v] = VariableInfo()
    return v
end

function MOI.add_variables(model::Optimizer, N::Int)
    vs = MOI.add_variables(model.optimizer, N)
    for v in vs
        model.original_variables[v] = VariableInfo()
    end
    return vs
end

function MOI.is_valid(model::Optimizer, v::MOI.VariableIndex)
    #@assert MOI.is_valid(model.quadratic_cache, v)
    return MOI.is_valid(model.optimizer, v)
end

function MOI.delete(model::Optimizer, v::MOI.VariableIndex)
    #MOI.delete(model.quadratic_cache, v)
    return MOI.delete(model.optimizer, v)
end

function MOI.get(model::Optimizer, attr::Type{MOI.VariableIndex}, name::String)
    MOI.get(model.optimizer, attr, name)
end
function MOI.get(model::Optimizer, attr::MOI.VariableName, v::MOI.VariableIndex)
    return MOI.get(model.optimizer, attr, v)
end
function MOI.set(
    model::Optimizer, attr::MOI.VariableName, v::MOI.VariableIndex, name::String
)
    return MOI.set(model.optimizer, attr, v, name)
end

##
## objective
##

function MOI.set(
    model::Optimizer, attr::MOI.ObjectiveSense, sense::MOI.OptimizationSense
)
    return MOI.set(model.optimizer, attr, sense)
end
function MOI.get(model::Optimizer, attr::MOI.ObjectiveSense)
    return MOI.get(model.optimizer, attr)
end
function MOI.set(
    model::Optimizer, attr::MOI.ObjectiveFunction{F}, f::F
) where {F <: Union{
    MOI.SingleVariable,
    MOI.ScalarAffineFunction{T}
}} where T
    model.quad_obj = nothing
    MOI.set(model.optimizer, attr, f)
    return
end
function MOI.set(
    model::Optimizer, attr::MOI.ObjectiveFunction{F}, f::F
) where {F <: MOI.ScalarQuadraticFunction{T}} where T
    model.quad_obj = f
    f_new = convert_to_affine(model, f)
    MOI.set(model.optimizer, MOI.ObjectiveFunction{MOI.ScalarAffineFunction{T}}(), f_new)
    return
end

function MOI.get(
    model::Optimizer,
    attr::MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{T}}
) where T
    if model.quad_obj === nothing
        error()
    else
        return copy(model.quad_obj)
    end
end
function MOI.get(
    model::Optimizer,
    attr::MOI.ObjectiveFunction{
        F
        }
) where F <: Union{
    MOI.SingleVariable,
    MOI.ScalarAffineFunction{T}
} where T
    if model.quad_obj !== nothing
        error()
    else
        return MOI.get(model.optimizer, attr)
    end
end

##
## constraints non-quadratic
##

function MOI.is_valid(
    model::Optimizer,
    ci::MOI.ConstraintIndex{F, S}
) where {F, S}
    return MOI.is_valid(model.optimizer, affine_index(ci))
end

function MOI.get(
    model::Optimizer, attr::MOI.ConstraintSet,
    ci::MOI.ConstraintIndex{F, S}
) where {F, S}
    return MOI.get(model.optimizer, attr, affine_index(ci))
end
function MOI.set(
    model::Optimizer, attr::MOI.ConstraintSet,
    ci::MOI.ConstraintIndex{F, S}, s
) where {F, S}
    return MOI.set(model.optimizer, attr, affine_index(ci), s)
end

function MOI.get(model::Optimizer, attr::MOI.ConstraintFunction,
    ci::MOI.ConstraintIndex{F, S}) where {F, S}
    return MOI.get(model.optimizer, attr, ci)
end
function MOI.set(model::Optimizer, attr::MOI.ConstraintFunction,
    ci::MOI.ConstraintIndex{F, S}, f) where {F, S}
    return MOI.set(model.optimizer, attr, ci, f)
end
function MOI.get(model::Optimizer, attr::MOI.ConstraintFunction,
    ci::MOI.ConstraintIndex{F, S}) where {F<:QuadraticFunction{T}, S} where T
    return get_quadratic(model, ci)
end
function MOI.set(model::Optimizer, attr::MOI.ConstraintFunction,
    ci::MOI.ConstraintIndex{F, S}, f) where {F<:QuadraticFunction{T}, S} where T
    # return MOI.set(model.optimizer, attr, ci, f)
    error("Operation not allowed. Quadratic functions cant be modified.")
end

function MOI.add_constraint(model::Optimizer, f::F, s::S
) where {F, S}
    ci = MOI.add_constraint(model.optimizer, f, s)
    return affine_index(ci)
end
function MOI.add_constraints(model::Optimizer, f::Vector{F}, s::Vector{S}
) where {F, S}
    cis = MOI.add_constraints(model.optimizer, f, s)
    return affine_index.(cis)
end
function MOI.add_constraint(model::Optimizer, f::F, s::S
) where {F<:QuadraticFunction{T}, S<:SCALAR_SETS} where T
    ci = MOI.add_constraint(model.optimizer, convert_to_affine(model, f), s)
    qci = quad_index(ci)
    store_quadratic!(model, qci, f)
    return qci
end
function MOI.add_constraints(model::Optimizer, f::Vector{F}, s::Vector{S}
) where {F<:QuadraticFunction{T}, S} where T
    cis = MOI.add_constraints(model.optimizer, convert_to_affine.(model, f), s)
    qcis = quad_index.(cis)
    for i in eachindex(cis)
        store_quadratic!(model, qcis[i], f[i])
    end
    return qcis
end

function MOI.delete(
    model::Optimizer,
    ci::MOI.ConstraintIndex{F, S}
) where {F, S}
    delete_quadratic!(model, ci)
    MOI.delete(model.optimizer, affine_index(ci))
end

function MOI.get(model::Optimizer, attr::MOI.ConstraintName, ci::Type{MOI.ConstraintIndex})
    return MOI.get(model.optimizer, attr, affine_index(ci))
end
function MOI.set(model::Optimizer, attr::MOI.ConstraintName, ci::Type{MOI.ConstraintIndex}, name::String)
    return MOI.set(model.optimizer, attr, affine_index(ci), name)
end
function MOI.get(model::Optimizer, attr::Type{MOI.ConstraintIndex}, name::String)
    return quad_index(MOI.get(model.optimizer, attr, name), attr)
end

function affine_index(ci::MOI.ConstraintIndex{F, S}) where {F,S}
    return ci
end
function affine_index(ci::MOI.ConstraintIndex{F, S}) where
    {F<:QuadraticFunction{T}, S} where T
    return MOI.ConstraintIndex{affine_type(F), S}(ci.value)
end
function quad_index(ci::MOI.ConstraintIndex{F, S}) where {F,S}
    return CI{quadratic_type(F),S}(ci.value)
end
function quad_index(ci::MOI.ConstraintIndex{F, S}, G) where {F,S}
    return ci
end
function quad_index(ci::MOI.ConstraintIndex{F, S},
    ci2::MOI.ConstraintIndex{F, S}) where {F, S}
    return MOI.ConstraintIndex{F, S}(ci.value)
end
function quad_index(ci::MOI.ConstraintIndex{F, S},
    ci2::MOI.ConstraintIndex{G, S}) where {F, G<:QuadraticFunction{T}, S} where T
    return MOI.ConstraintIndex{G, S}(ci.value)
end
function quad_index(ci::MOI.ConstraintIndex{F, S},
    attr::Type{MOI.ConstraintIndex{F, S}}) where {F, S}
    return MOI.ConstraintIndex{F, S}(ci.value)
end
function quad_index(ci::MOI.ConstraintIndex{F, S},
    attr::Type{MOI.ConstraintIndex{G, S}}) where {F, G<:QuadraticFunction{T}, S} where T
    return MOI.ConstraintIndex{G, S}(ci.value)
end

##
## SingleVariable-in-Set
##

_bounds(s::MOI.GreaterThan{Float64}) = (s.lower, Inf)
_bounds(s::MOI.LessThan{Float64}) = (-Inf, s.upper)
_bounds(s::MOI.EqualTo{Float64}) = (s.value, s.value)
_bounds(s::MOI.Interval{Float64}) = (s.lower, s.upper)

function _throw_if_existing_lower(
    bound::BoundType, var_type::VariableType,
    new_set::Type{<:MOI.AbstractSet},
    variable::MOI.VariableIndex
)
    existing_set = if bound == LESS_AND_GREATER_THAN || bound == GREATER_THAN
        MOI.GreaterThan{Float64}
    elseif bound == INTERVAL
        MOI.Interval{Float64}
    elseif bound == EQUAL_TO
        MOI.EqualTo{Float64}
    elseif var_type == SEMIINTEGER
        MOI.Semiinteger{Float64}
    elseif var_type == SEMICONTINUOUS
        MOI.Semicontinuous{Float64}
    else
        nothing  # Also covers `NONE` and `LESS_THAN`.
    end
    if existing_set !== nothing
        throw(MOI.LowerBoundAlreadySet{existing_set, new_set}(variable))
    end
end
function _throw_if_existing_upper(
    bound::BoundType,
    var_type::VariableType,
    new_set::Type{<:MOI.AbstractSet},
    variable::MOI.VariableIndex
)
    existing_set = if bound == LESS_AND_GREATER_THAN || bound == LESS_THAN
        MOI.LessThan{Float64}
    elseif bound == INTERVAL
        MOI.Interval{Float64}
    elseif bound == EQUAL_TO
        MOI.EqualTo{Float64}
    elseif var_type == SEMIINTEGER
        MOI.Semiinteger{Float64}
    elseif var_type == SEMICONTINUOUS
        MOI.Semicontinuous{Float64}
    else
        nothing  # Also covers `NONE` and `GREATER_THAN`.
    end
    if existing_set !== nothing
        throw(MOI.UpperBoundAlreadySet{existing_set, new_set}(variable))
    end
end
function cache_bounds(
    model::Optimizer, f::MOI.SingleVariable, s::MOI.LessThan{T}) where T
    info = model.original_variables[f.variable]
    _throw_if_existing_upper(info.bound, info.type, MOI.LessThan{T}, f.variable)
    info.bound = info.bound == GREATER_THAN ? LESS_AND_GREATER_THAN : LESS_THAN
    lb, ub = _bounds(s)
    info.upper = ub
    return
end
function cache_bounds(
    model::Optimizer, f::MOI.SingleVariable, s::MOI.GreaterThan{T}) where T
    info = model.original_variables[f.variable]
    _throw_if_existing_lower(info.bound, info.type, MOI.GreaterThan{T}, f.variable)
    info.bound = info.bound == LESS_THAN ? LESS_AND_GREATER_THAN : GREATER_THAN
    lb, ub = _bounds(s)
    info.lower = lb
    return
end
function cache_bounds(
    model::Optimizer, f::MOI.SingleVariable, s::MOI.EqualTo{T}) where T
    info = model.original_variables[f.variable]
    _throw_if_existing_lower(info.bound, info.type, MOI.EqualTo{T}, f.variable)
    _throw_if_existing_upper(info.bound, info.type, MOI.EqualTo{T}, f.variable)
    info.bound = EQUAL_TO
    lb, ub = _bounds(s)
    info.lower = lb
    info.upper = ub
    return
end
function cache_bounds(
    model::Optimizer, f::MOI.SingleVariable, s::MOI.Interval{T}) where T
    info = model.original_variables[f.variable]
    _throw_if_existing_lower(info.bound, info.type, MOI.Interval{T}, f.variable)
    _throw_if_existing_upper(info.bound, info.type, MOI.Interval{T}, f.variable)
    info.bound = INTERVAL
    lb, ub = _bounds(s)
    info.lower = lb
    info.upper = ub
    return
end

function MOI.add_constraints(
    model::Optimizer, f::Vector{MOI.SingleVariable}, s::Vector{S}
) where {S <: SCALAR_SETS}
    c = MOI.add_constraints(model.optimizer, f, s)
    for i in eachindex(f)
        cache_bounds(model, f[i], s[i])
        model.ci_to_var[c[i]] = f[i].variable
    end
    return c
end
function MOI.add_constraint(
    model::Optimizer, f::MOI.SingleVariable, s::S
) where {S <: SCALAR_SETS}
    ci = MOI.add_constraint(model.optimizer, f, s)
    cache_bounds(model, f, s)
    model.ci_to_var[ci] = f.variable
    return ci
end

function MOI.set(
    model::Optimizer, ::MOI.ConstraintFunction,
    c::MOI.ConstraintIndex{MOI.SingleVariable, <:Any}, ::MOI.SingleVariable
)
    return throw(MOI.SettingSingleVariableFunctionNotAllowed())
end
function MOI.set(
    model::Optimizer, ::MOI.ConstraintSet,
    c::MOI.ConstraintIndex{MOI.SingleVariable, S}, s::S
) where S<:Union{MOI.Interval{T}, MOI.EqualTo{T}} where T
    MOI.throw_if_not_valid(model.optimizer, c)
    MOI.set(model.optimizer, MOI.ConstraintSet(), c, s)
    lower, upper = _bounds(s)
    var = model.ci_to_var[c]
    info = model.original_variables[var]
    info.lower = lower
    info.upper = upper
    return
end
function MOI.set(
    model::Optimizer, ::MOI.ConstraintSet,
    c::MOI.ConstraintIndex{MOI.SingleVariable, S}, s::S
) where S<:Union{MOI.LessThan{T}} where T
    MOI.throw_if_not_valid(model.optimizer, c)
    MOI.set(model.optimizer, MOI.ConstraintSet(), c, s)
    lower, upper = _bounds(s)
    var = model.ci_to_var[c]
    info = model.original_variables[var]
    info.upper = upper
    return
end
function MOI.set(
    model::Optimizer, ::MOI.ConstraintSet,
    c::MOI.ConstraintIndex{MOI.SingleVariable, S}, s::S
) where S<:Union{MOI.GreaterThan{T}} where T
    MOI.throw_if_not_valid(model.optimizer, c)
    MOI.set(model.optimizer, MOI.ConstraintSet(), c, s)
    lower, upper = _bounds(s)
    var = model.ci_to_var[c]
    info = model.original_variables[var]
    info.lower = lower
    return
end


function MOI.delete(model::Optimizer,
    c::MOI.ConstraintIndex{MOI.SingleVariable, MOI.LessThan{T}}
) where T
    MOI.throw_if_not_valid(model.optimizer, c)
    var = model.ci_to_var[c]
    MOI.delete(model.optimizer, c)
    delete!(model.ci_to_var, c)
    info = model.original_variables[var]
    info.upper = Inf
    info.bound = info.bound == LESS_AND_GREATER_THAN ? GREATER_THAN : NONE
    return
end
function MOI.delete(model::Optimizer,
    c::MOI.ConstraintIndex{MOI.SingleVariable, MOI.GreaterThan{T}}
) where T
    MOI.throw_if_not_valid(model.optimizer, c)
    var = model.ci_to_var[c]
    MOI.delete(model.optimizer, c)
    delete!(model.ci_to_var, c)
    info = model.original_variables[var]
    info.lower = -Inf
    info.bound = info.bound == LESS_AND_GREATER_THAN ? LESS_THAN : NONE
    return
end
function MOI.delete(model::Optimizer,
    c::MOI.ConstraintIndex{MOI.SingleVariable, S}
) where S<:Union{MOI.Interval{T}, MOI.EqualTo{T}} where T
    MOI.throw_if_not_valid(model.optimizer, c)
    var = model.ci_to_var[c]
    MOI.delete(model.optimizer, c)
    delete!(model.ci_to_var, c)
    info = model.original_variables[var]
    info.lower = -Inf
    info.upper = +Inf
    info.bound = NONE
    return
end

scalar_type(S::MOI.ZeroOne) = BINARY
scalar_type(S::MOI.Integer) = INTEGER
function MOI.add_constraints(
    model::Optimizer, f::Vector{MOI.SingleVariable}, s::Vector{S}
) where {S <: SCALAR_TYPES}
    c = MOI.add_constraints(model.optimizer, f, s)
    for i in eachindex(f)
        info = model.original_variables[f[i].variable]
        if info.type != BINARY && info.type != INTEGER
            info.type = scalar_type(S)
        else
            error("Variable $(f[i].variable) is already of type $(info.type)")
        end
    end
    for i in eachindex(c)
        model.ci_to_var[c[i]] = f[i].variable
    end
    return c
end
function MOI.add_constraint(
    model::Optimizer, f::MOI.SingleVariable, s::S
) where {S <: SCALAR_TYPES}
    ci = MOI.add_constraint(model.optimizer, f, s)
    info = model.original_variables[f.variable]
    if info.type != BINARY && info.type != INTEGER
        info.type = scalar_type(S)
    else
        error("Variable $(f.variable) is already of type $(info.type)")
    end
    model.ci_to_var[ci] = f.variable
    return ci
end
function MOI.delete(model::Optimizer,
    c::MOI.ConstraintIndex{MOI.SingleVariable, S}
) where S<:SCALAR_TYPES
    MOI.throw_if_not_valid(model.optimizer, c)
    var = model.ci_to_var[c]
    MOI.delete(model.optimizer, c)
    delete!(model.ci_to_var, c)
    info = model.original_variables[var]
    info.type = CONTINUOUS
    return
end

lower(info) = info.type == BINARY ? zero(typeof(info.lower)) : info.lower
upper(info) = info.type == BINARY ? one(typeof(info.lower)) : info.upper
function get_precision(model::Optimizer{T}, x) where T
    info = model.original_variables[x]
    a = model.global_initial_precision
    b = info.initial_precision
    pre = min(isnan(a) ? one(T) : a, isnan(b) ? one(T) : b)
    if info.type == BINARY
        pre = one(T)
    end
    @assert zero(T) < pre <= one(T)
    ceil(Int, -log2(pre))
end
function MOI.optimize!(model::Optimizer)

    T = Float64

    QT = keys(model.pair_to_var)

    # variables to expand
    DS = Set()
    # build graph
    neighbors = Dict()
    degree = Dict()
    for (i,j) in keys(model.pair_to_var)
        if i == j
            push!(DS, i)
        else
            for (a,b) in [(i,j), (j,i)]
                if haskey(neighbors, a)
                    push!(neighbors[a], b)
                    degree[a] += 1
                else
                    neighbors[a] = [b]
                    degree[a] = 1
                end
            end
        end
    end

    # Based in: https://github.com/JuliaGraphs/LightGraphs.jl/blob/v1.3.1/src/vertexcover/degree_vertex_cover.jl
    degree_queue = PriorityQueue(Base.Order.Reverse, degree)
    # Loops in the graph must be added to this cover
    for v in DS
        degree_queue[v] = 0
        @inbounds @simd for u in neighbors[v]
            if !(v in DS)#!in_cover[u] 
                degree_queue[u] -= 1
            end
        end
    end
    # length_cover = length(DS)
    while !isempty(degree_queue) && peek(degree_queue)[2] > 0
        v = dequeue!(degree_queue)
        # in_cover[v] = true
        push!(DS, v)
        # length_cover += 1
        @inbounds @simd for u in neighbors[v]
            if !(v in DS)#!in_cover[u] 
                degree_queue[u] -= 1
            end
        end
    end

    # Bounds detection
    for pair in QT
        for x in pair
            info = model.original_variables[x]
            if !(upper(info) < Inf)
                error("Variable $x has no upper bound.")
            end
            if !(lower(info) > -Inf)
                error("Variable $x has no lower bound.")
            end
        end
    end

    QT = keys(model.pair_to_var)
    #
    preΔx = MOI.add_variables(model.optimizer, length(DS))
    Δx = Dict()
    for (i,v) in enumerate(DS)
        Δx[v] = preΔx[i]
    end
    #
    w = model.pair_to_var
    #
    preΔw = MOI.add_variables(model.optimizer, length(w))
    Δw = Dict()
    for (i,p) in enumerate(QT)
        Δw[p] = preΔw[i]
    end
    #
    z = Dict()
    for v in DS
        z[v] = MOI.add_variables(model.optimizer, get_precision(model, v))#VI[]
    end
    #
    xh = Dict()
    for (xa,xb) in QT
        if xb in DS
            xi = xa
            xj = xb # in DS
        else
            xi = xb
            xj = xa
        end
        xh[(xa,xb)] = MOI.add_variables(model.optimizer, get_precision(model, xj))#VI[]
    end

    # zeros are useless in the paper

    # eq 28 - binary expansion of xj
    f28 = []
    s28 = []
    for xj in DS
        info = model.original_variables[xj]
        Xu = upper(info)
        Xl = lower(info)
        Δxj = Δx[xj]
        zj = z[xj]
        terms = [
            MOI.ScalarAffineTerm(-T(1), xj),
            MOI.ScalarAffineTerm(Xu-Xl, Δxj)
        ]
        for l in 1:get_precision(model, xj)
            push!(terms, MOI.ScalarAffineTerm( (Xu-Xl)*T(2)^(-T(l)), zj[l]))
        end
        push!(f28, MOI.ScalarAffineFunction(terms, zero(T)))
        push!(s28, MOI.EqualTo{T}(-Xl))
    end
    c28 = MOI.add_constraints(model.optimizer, f28, s28)

    # eq 29 - binary expansion of the product
    f29 = []
    for (xa,xb) in QT
        if xb in DS
            xi = xa
            xj = xb # in DS
        else
            xi = xb
            xj = xa
        end
        info = model.original_variables[xj]
        Xu = upper(info)
        Xl = lower(info)
        #order is important in the pairs
        Δwij = Δw[(xa,xb)]
        wij = w[(xa,xb)]
        xhij = xh[(xa,xb)] # vector
        terms = [
            MOI.ScalarAffineTerm(-one(T), wij),
            MOI.ScalarAffineTerm(Xu-Xl, Δwij),
            MOI.ScalarAffineTerm(Xl, xi) #missing in the paper
        ]
        for l in 1:get_precision(model, xj)
            push!(terms, MOI.ScalarAffineTerm( (Xu-Xl)*T(2)^(-T(l)), xhij[l]))
        end
        push!(f29, MOI.ScalarAffineFunction(terms, zero(T)))
    end
    s29 = [MOI.EqualTo{T}(zero(T)) for i in eachindex(f29)]
    c29 = MOI.add_constraints(model.optimizer, f29, s29)

    # eq 30 - bound on \Delta xj
    f30a = []
    f30b = []
    s30b = []
    for xj in DS
        push!(f30a, MOI.SingleVariable(Δx[xj]))
        push!(f30b, MOI.SingleVariable(Δx[xj]))
        push!(s30b, MOI.LessThan{T}(T(2)^(-T(get_precision(model, xj)))))
    end
    s30a = [MOI.GreaterThan{T}(zero(T)) for i in eachindex(f30a)]
    c30a = MOI.add_constraints(model.optimizer, f30a, s30a)
    c30b = MOI.add_constraints(model.optimizer, f30b, s30b)

    # eq 31 - McCormick in \Delta wij
    f31a = []
    f31b = []
    s31a = []
    s31b = []
    # 32
    f32a = []
    f32b = []
    s32a = []
    s32b = []
    for (xa,xb) in QT
        if xb in DS
            xi = xa
            xj = xb # in DS
        else
            xi = xb
            xj = xa
        end
        info_i = model.original_variables[xi]
        Xu_i = upper(info_i)
        Xl_i = lower(info_i)
        Δwij = Δw[(xa,xb)]
        Δxj = Δx[xj]
        p = get_precision(model, xj)
        # 31
        terms_31a = [
            MOI.ScalarAffineTerm(one(T), Δwij),
            MOI.ScalarAffineTerm(-Xu_i, Δxj), # review here if both are indeed I
            MOI.ScalarAffineTerm(-T(2)^(-T(p)), xi), # review here if both are indeed I
        ]
        push!(f31a, MOI.ScalarAffineFunction(terms_31a, zero(T)))
        push!(s31a, MOI.GreaterThan{T}(-Xu_i*T(2)^(-T(p))))
        terms_31b = [
            MOI.ScalarAffineTerm(one(T), Δwij),
            MOI.ScalarAffineTerm(-Xl_i, Δxj), # review here if both are indeed I
            MOI.ScalarAffineTerm(-T(2)^(-T(p)), xi), # review here if both are indeed I
        ]
        push!(f31b, MOI.ScalarAffineFunction(terms_31b, zero(T)))
        push!(s31b, MOI.LessThan{T}(-Xl_i*T(2)^(-T(p))))
        # 32
        terms_32a = [
            MOI.ScalarAffineTerm(one(T), Δwij),
            MOI.ScalarAffineTerm(-Xl_i, Δxj), # review here if both are indeed I
        ]
        push!(f32a, MOI.ScalarAffineFunction(terms_32a, zero(T)))
        push!(s32a, MOI.GreaterThan{T}(zero(T)))
        terms_32b = [
            MOI.ScalarAffineTerm(one(T), Δwij),
            MOI.ScalarAffineTerm(-Xu_i, Δxj), # review here if both are indeed I
        ]
        push!(f32b, MOI.ScalarAffineFunction(terms_32b, zero(T)))
        push!(s32b, MOI.LessThan{T}(zero(T)))
    end
    c31a = MOI.add_constraints(model.optimizer, f31a, s31a)
    c31b = MOI.add_constraints(model.optimizer, f31b, s31b)
    c32a = MOI.add_constraints(model.optimizer, f32a, s32a)
    c32b = MOI.add_constraints(model.optimizer, f32b, s32b)

    # eq 33 - Disjunction
    f33a = []
    f33b = []
    s33a = []
    s33b = []
    # 34
    f34a = []
    f34b = []
    s34a = []
    s34b = []
    for (xa,xb) in QT
        if xb in DS
            xi = xa
            xj = xb # in DS
        else
            xi = xb
            xj = xa
        end
        info_i = model.original_variables[xi]
        Xu_i = upper(info_i)
        Xl_i = lower(info_i)
        zj = z[xj]
        xhij = xh[(xa,xb)]
        # 33
        for l in 1:get_precision(model, xj)
            terms_33a = [
                MOI.ScalarAffineTerm(one(T), xhij[l]),
                MOI.ScalarAffineTerm(-Xl_i, zj[l]), # review here if both are indeed I
            ]
            push!(f33a, MOI.ScalarAffineFunction(terms_33a, zero(T)))
            push!(s33a, MOI.GreaterThan{T}(zero(T)))
            terms_33b = [
                MOI.ScalarAffineTerm(one(T), xhij[l]),
                MOI.ScalarAffineTerm(-Xu_i, zj[l]), # review here if both are indeed I
            ]
            push!(f33b, MOI.ScalarAffineFunction(terms_33b, zero(T)))
            push!(s33b, MOI.LessThan{T}(zero(T)))
            # 34
            terms_34a = [
                MOI.ScalarAffineTerm( one(T), xi),
                MOI.ScalarAffineTerm(-one(T), xhij[l]),
                MOI.ScalarAffineTerm(Xl_i, zj[l]), # review here if both are indeed I
            ]
            push!(f34a, MOI.ScalarAffineFunction(terms_34a, zero(T)))
            push!(s34a, MOI.GreaterThan{T}(Xl_i))
            terms_34b = [
                MOI.ScalarAffineTerm( one(T), xi),
                MOI.ScalarAffineTerm(-one(T), xhij[l]),
                MOI.ScalarAffineTerm(Xu_i, zj[l]), # review here if both are indeed I
            ]
            push!(f34b, MOI.ScalarAffineFunction(terms_34b, zero(T)))
            push!(s34b, MOI.LessThan{T}(Xu_i))
        end
    end
    c33a = MOI.add_constraints(model.optimizer, f33a, s33a)
    c33b = MOI.add_constraints(model.optimizer, f33b, s33b)
    c34a = MOI.add_constraints(model.optimizer, f34a, s34a)
    c34b = MOI.add_constraints(model.optimizer, f34b, s34b)

    # 37 - z is binary
    f37 = []
    s37 = []
    for zj in values(z), zjl in zj
        push!(f37, MOI.SingleVariable(zjl))
        push!(s37, MOI.ZeroOne())
    end
    c37 = MOI.add_constraints(model.optimizer, f37, s37)

    # TODO: deal with integers
    # TODO: use model to hold intercepted ctrs?
    return MOI.optimize!(model.optimizer)
end


function MOI.get(model::Optimizer, ::MOI.VariablePrimal, vi::VI)
    return MOI.get(model.optimizer, MOI.VariablePrimal(), vi)
end

function MOI.get(model::Optimizer, ::MOI.ConstraintDual, 
                 ci::CI{F,S}) where {F, S}
    error("No duals available")
end

function MOI.get(model::Optimizer, ::MOI.ConstraintPrimal, 
                 ci::CI{F,S}) where {F, S}
    return MOI.get(model.optimizer, MOI.ConstraintPrimal(), ci)
end
function MOI.get(model::Optimizer, ::MOI.ConstraintPrimal, 
    ci::CI{F,S}) where {F <: QuadraticFunction{T}, S} where T
    return MOI.get(model.optimizer, MOI.ConstraintPrimal(), affine_index(ci))
end

function MOI.get(model::Optimizer, ::T) where {
    T <: Union{
        MOI.TerminationStatus,
        MOI.ObjectiveValue,
        MOI.PrimalStatus,
    }
}
    return MOI.get(model.optimizer, T())
end

function MOI.get(model::Optimizer, attr::Union{
    MOI.AbstractModelAttribute,
    MOI.AbstractOptimizerAttribute
    })
    return MOI.get(model.optimizer, attr)
end

function MOI.get(model::Optimizer, attr::MOI.RawStatusString)
    return "Raw status from solver: " * 
        MOI.get(model.optimizer, MOI.SolverName()) * ", is: " *
        MOI.get(model.optimizer, MOI.RawStatusString())
end

function MOI.get(
    model::Optimizer,
    ::MOI.ListOfConstraintIndices{F, S}
) where {S, F<:Union{
    MOI.ScalarAffineFunction{Float64},
    MOI.VectorAffineFunction{Float64},
    MOI.VectorOfVariables
}}
    in_opt = MOI.get(model.optimizer, MOI.ListOfConstraintIndices{F, S}())
    quads = get_indices(model, F)
    return setdiff!(in_opt, affine_index.(quads))
end
function MOI.get(
    model::Optimizer,
    ::MOI.ListOfConstraintIndices{F, S}
) where {S, F<:Union{
    MOI.ScalarQuadraticFunction{Float64},
    MOI.VectorQuadraticFunction{Float64},
}}
    in_opt = MOI.get(model.optimizer, MOI.ListOfConstraintIndices{affine_type(F), S}())
    quads = get_indices(model, F)
    return intersect!(quad_index.(in_opt), quads)
end

function MOI.get(model::Optimizer, attr::MOI.ObjectiveFunctionType)
    if model.quad_obj === nothing
        return MOI.get(model.optimizer, attr)
    else
        return typeof(model.quad_obj)
    end
end

function MOI.get(model::Optimizer, attr::MOI.NumberOfVariables)
    return MOI.get(model.optimizer, attr)
end
function MOI.get(model::Optimizer, attr::MOI.ListOfVariableIndices)
    return MOI.get(model.optimizer, attr)
end

MOI.get(model::Optimizer, attr::MOI.RawSolver) = MOI.get(model.optimizer, attr)

# we will need to propagate the primal start
function MOI.set(
    model::Optimizer,
    attr::MOI.VariablePrimalStart,
    x::MOI.VariableIndex,
    value::Union{Nothing, Float64}
)
    MOI.set(model.optimizer, attr, x, value)
    return
end

function MOI.get(
    model::Optimizer, attr::MOI.VariablePrimalStart, x::MOI.VariableIndex
)
    return MOI.get(model.optimizer, attr, x)
end

struct VariablePrecision end
struct GlobalVariablePrecision end

function MOI.set(
    model::Optimizer,
    attr::VariablePrecision,
    x::MOI.VariableIndex,
    value::Union{Nothing, Float64}
)
    val = value === nothing ? NaN : value
    @assert 0 < val <= 1
    model.original_variables[x].initial_precision = val
    return
end
function MOI.get(
    model::Optimizer, attr::VariablePrecision, x::MOI.VariableIndex
)
    return model.original_variables[x].initial_precision
end

function MOI.set(
    model::Optimizer,
    attr::GlobalVariablePrecision,
    value::Union{Nothing, Float64}
)
    val = value === nothing ? NaN : value
    @assert 0 < val <= 1
    model.global_initial_precision = val
    return
end
function MOI.get(
    model::Optimizer, attr::GlobalVariablePrecision, x::MOI.VariableIndex
)
    return model.global_initial_precision
end

function MOI.get(model::Optimizer, ::MOI.NumberOfConstraints{F, S}) where {F, S}
    # TODO: this could be more efficient.
    return length(MOI.get(model, MOI.ListOfConstraintIndices{F, S}()))
end


function MOI.get(model::Optimizer, ::MOI.ListOfConstraints)
    constraints = Set{Tuple{DataType, DataType}}()
    error("TODO")
end

function ordered_term_indices(t::MOI.ScalarQuadraticTerm)
    return VI.(minmax(t.variable_index_1.value, t.variable_index_2.value))
end
function ordered_term_indices(t::Union{MOI.VectorAffineTerm, MOI.VectorQuadraticTerm})
    return (t.output_index, ordered_term_indices(t.scalar_term)...)
end
function get_affine_part(f::MOI.ScalarQuadraticFunction{T}) where T
    return MOI.ScalarAffineFunction{T}(f.affine_terms, f.constant)
end
function get_affine_part(f::MOI.VectorQuadraticFunction{T}) where T
    return MOI.VectorAffineFunction{T}(f.affine_terms, f.constants)
end
function convert_to_affine(model::Optimizer, f::QuadraticFunction{T}) where T
    fc = MOIU.canonical(f)
    for t in fc.quadratic_terms
        aff_term = build_affine_term(model, t)
        push!(fc.affine_terms, aff_term)
    end
    return get_affine_part(fc)
end
function build_affine_term(model::Optimizer{T}, t::MOI.ScalarQuadraticTerm) where T
    pair = ordered_term_indices(t)
    var = add_or_get_variable(model, pair)
    m = pair[1] == pair[2] ? T(1/2) : T(1)
    return MOI.ScalarAffineTerm(m*MOI.coefficient(t), var)
end
function build_affine_term(model::Optimizer{T}, t::MOI.VectorQuadraticTerm) where T
    triple = ordered_term_indices(t)
    var = add_or_get_variable(model, (triple[2], triple[3]))
    m = triple[2] == triple[3] ? T(1/2) : T(1)
    return MOI.VectorAffineTerm(triple[1],
        MOI.ScalarAffineTerm(m*MOI.coefficient(t), var))
end
function add_or_get_variable(model::Optimizer, pair)
    # for each unique pair we need a single variable
    if haskey(model.pair_to_var, pair)
        return model.pair_to_var[pair]
    else
        var = MOI.add_variable(model.optimizer)
        model.pair_to_var[pair] = var
        return var
    end
end