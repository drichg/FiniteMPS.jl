"""
     pushleft!(::AbstractEnvironment)

Push left the given environment object, i.e. `Center == [i, j]` to `[i, j - 1]`.
"""
function pushleft!(obj::SimpleEnvironment{L,2,T}) where {L,T<:Tuple{AdjointMPS,MPS}}
     si = obj.Center[2]
     @assert si > 1

     obj.Er[si-1] = _pushleft(obj.Er[si], obj[1][si], obj[2][si])
     obj.Center[2] -= 1
     return obj
end

function pushleft!(obj::SparseEnvironment{L,3,T}) where {L,T<:Tuple{AdjointMPS,SparseMPO,MPS}}
     si = obj.Center[2]
     @assert si > 1

     sz = size(obj[2][si])

     Er_next = SparseRightTensor(nothing, sz[1])
     if get_num_workers() > 1 # multi-processing

          lsEr = let Er = obj.Er[si], A = obj[1][si], H = obj[2][si], B = obj[3][si]
               valid_idx = [(j, i) for j in 1:sz[1] for i in filter(x -> !isnothing(H[j, x]) && !isnothing(Er[x]), 1:sz[2])]
               pmap(valid_idx) do (j, i)
                    _pushleft(Er[i], A, H[j, i], B), j, i
               end
          end

          for (Er, j, i) in lsEr
               Er_next[j] = axpy!(true, Er, Er_next[j])
          end

     else
          let Er = obj.Er[si], A = obj[1][si], H = obj[2][si], B = obj[3][si]
               @threads for j in 1:sz[1]
                    @floop GlobalThreadsExecutor for i in filter(x -> !isnothing(H[j, x]) && !isnothing(Er[x]), 1:sz[2])

                         Er_i = _pushleft(Er[i], A, H[j, i], B)
                         @reduce() do (Er_cum = nothing; Er_i)
                              Er_cum = axpy!(true, Er_i, Er_cum)
                         end
                    end
                    Er_next[j] = Er_cum
               end
          end
     end
     obj.Er[si-1] = Er_next

     obj.Center[2] -= 1
     return obj
end

function _pushleft(Er::LocalRightTensor{2}, A::AdjointMPSTensor{3}, B::MPSTensor{3}; kwargs...)
     # if rank(A, 1) == 1
     @tensor tmp[e; b] := (B.A[e c d] * Er.A[d a]) * A.A[a b c]
     # else
     #      @tensor tmp[e; b] := (B.A[e c d] * Er.A[d a]) * A.A[c a b]
     # end
     return LocalRightTensor(tmp, Er.tag)
end
function _pushleft(Er::LocalRightTensor{2}, A::AdjointMPSTensor{3}, H::IdentityOperator, B::MPSTensor{3}; kwargs...)
     return _pushleft(Er, A, B) * H.strength
end

function _pushleft(Er::LocalRightTensor{2}, A::AdjointMPSTensor{3}, H::LocalOperator{2,1}, B::MPSTensor{3}; kwargs...)

     # D^3d + D^2d^2χ + D^3dχ
     # if rank(A, 1) == 1
          @tensor tmp[e g; b] := ((B.A[e f d] * Er.A[d a]) * H.A[g c f]) * A.A[a b c]
     # else
     #      @tensor Er[e g; b] := ((B.A[e f d] * Er.A[d a]) * H.A[g c f]) * A.A[c a b]
     # end

     return LocalRightTensor(tmp * H.strength, (Er.tag[1], H.tag[1][1], Er.tag[2]))
end

function _pushleft(Er::LocalRightTensor{2}, A::AdjointMPSTensor{3}, H::LocalOperator{1,1}, B::MPSTensor{3}; kwargs...)
     # if rank(A, 1) == 1
          @tensor tmp[e; b] := ((B.A[e f d] * Er.A[d a]) * H.A[c f]) * A.A[a b c]
     # else
     #      @tensor Er[e; b] := ((B.A[e f d] * Er.A[d a]) * H.A[c f]) * A.A[c a b]
     # end
     return LocalRightTensor(tmp * H.strength, Er.tag)
end

function _pushleft(Er::LocalRightTensor{3}, A::AdjointMPSTensor{3}, H::LocalOperator{1,1}, B::MPSTensor{3}; kwargs...)
     # if rank(A, 1) == 1
          @tensor tmp[e g; b] := ((B.A[e f d] * H.A[c f]) * Er.A[d g a]) * A.A[a b c]
     # else
     #      @tensor Er[e g; b] := ((B.A[e f d] * H.A[c f]) * Er.A[d g a]) * A.A[c a b]
     # end
     return LocalRightTensor(tmp * H.strength, Er.tag)
end

function _pushleft(Er::LocalRightTensor{3}, A::AdjointMPSTensor{3}, H::LocalOperator{1,2}, B::MPSTensor{3}; kwargs...)
     # if rank(A, 1) == 1
          @tensor tmp[e; b] := ((B.A[e f d] * Er.A[d g a]) * H.A[c f g]) * A.A[a b c]
     # else
     #      @tensor Er[e; b] := ((B.A[e f d] * Er.A[d g a]) * H.A[c f g]) * A.A[c a b]
     # end
     return LocalRightTensor(tmp * H.strength, (Er.tag[1], Er.tag[3]))
end