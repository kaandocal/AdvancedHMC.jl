# TODO: add more target distributions and make them iteratable
# TODO: Integrate with https://github.com/xukai92/VecTargets.jl to achieve goal noted 
#       above.

# Dimension of testing distribution
const D = 5
# Tolerance ratio
const TRATIO = Int == Int64 ? 1 : 2
# Deterministic tolerance
const DETATOL = 1e-3 * D * TRATIO
# Random tolerance
const RNDATOL = 5e-2 * D * TRATIO * 2

# Convenience
# TODO: Remove this if made available in some other package.
using Distributions: Distributions
using Bijectors: Bijectors
struct LogDensityDistribution{D<:Distributions.Distribution}
    dist::D
end

LogDensityProblems.dimension(d::LogDensityDistribution) = length(d.dist)
function LogDensityProblems.logdensity(ld::LogDensityDistribution, y)
    d = ld.dist
    b = Bijectors.inverse(Bijectors.bijector(d))
    x, logjac = Bijectors.with_logabsdet_jacobian(b, y)
    return logpdf(d, x) + logjac
end
LogDensityProblems.capabilities(::Type{<:LogDensityDistribution}) = LogDensityProblems.LogDensityOrder{0}()

# Hand-coded multivariate Gaussian

struct Gaussian{Tm, Ts}
    m::Tm
    s::Ts
end

function ℓπ_gaussian(g::AbstractVecOrMat{T}, s) where {T}
    return .-(log(2 * T(pi)) .+ 2 .* log.(s) .+ abs2.(g) ./ s.^2) ./ 2
end

ℓπ_gaussian(m, s, x) = ℓπ_gaussian(m .- x, s)

LogDensityProblems.dimension(g::Gaussian) = dim(g.m)
LogDensityProblems.logdensity(g::Gaussian, x) = ℓπ_gaussian(g.m. g.s, x)
LogDensityProblems.capabilities(::Type{<:Gaussian}) = LogDensityProblems.LogDensityOrder{0}()

function ∇ℓπ_gaussianl(m, s, x)
    g = m .- x
    v = ℓπ_gaussian(g, s)
    return v, g
end

function get_ℓπ(g::Gaussian)
    ℓπ(x::AbstractVector) = sum(ℓπ_gaussian(g.m, g.s, x))
    ℓπ(x::AbstractMatrix) = dropdims(sum(ℓπ_gaussian(g.m, g.s, x); dims=1); dims=1)
    return ℓπ
end

function get_∇ℓπ(g::Gaussian)
    function ∇ℓπ(x::AbstractVector)
        val, grad = ∇ℓπ_gaussianl(g.m, g.s, x)
        return sum(val), grad
    end
    function ∇ℓπ(x::AbstractMatrix)
        val, grad = ∇ℓπ_gaussianl(g.m, g.s, x)
        return dropdims(sum(val; dims=1); dims=1), grad
    end
    return ∇ℓπ
end

ℓπ = get_ℓπ(Gaussian(zeros(D), ones(D)))
∂ℓπ∂θ = get_∇ℓπ(Gaussian(zeros(D), ones(D)))

# For the Turing model
# @model gdemo() = begin
#     s ~ InverseGamma(2, 3)
#     m ~ Normal(0, sqrt(s))
#     1.5 ~ Normal(m, sqrt(s))
#     2.0 ~ Normal(m, sqrt(s))
#     return s, m
# end

using Distributions: logpdf, InverseGamma, Normal
using Bijectors: invlink, logpdf_with_trans

function invlink_gdemo(θ)
    s = invlink(InverseGamma(2, 3), θ[1])
    m = θ[2]
    return [s, m]
end

function ℓπ_gdemo(θ)
    s, m = invlink_gdemo(θ)
    logprior = logpdf_with_trans(InverseGamma(2, 3), s, true) + logpdf(Normal(0, sqrt(s)), m)
    loglikelihood = logpdf(Normal(m, sqrt(s)), 1.5) + logpdf(Normal(m, sqrt(s)), 2.0)
    return logprior + loglikelihood
end

# Make compat with `LogDensityProblems`.
LogDensityProblems.dimension(::typeof(ℓπ_gdemo)) = 2
LogDensityProblems.logdensity(::typeof(ℓπ_gdemo), θ) = ℓπ_gdemo(θ)
LogDensityProblems.capabilities(::Type{typeof(ℓπ_gdemo)}) = LogDensityProblems.LogDensityOrder{0}()

test_show(x) = test_show(s -> length(s) > 0, x)
function test_show(pred, x)
    io = IOBuffer(; append = true)
    show(io, x)
    s = read(io, String)
    @test pred(s)
end
