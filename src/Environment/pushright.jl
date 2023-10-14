"""
     pushright!(::AbstractEnvironment)

Push right the given environment object, i.e. `Center == [i, j]` to `[i + 1, j]`.
"""
function pushright!(obj::SimpleEnvironment{L,2,T}) where {L,T<:Tuple{AdjointMPS,MPS}}
     si = obj.Center[1]
     @assert si < L

     obj.El[si+1] = _pushright(obj.El[si], obj[1][si], obj[2][si])
     obj.Center[1] += 1
     return obj
end

function pushright!(obj::SparseEnvironment{L,3,T}) where {L,T<:Tuple{AdjointMPS,SparseMPO,MPS}}
     si = obj.Center[1]
     @assert si < L

     sz = size(obj[2][si])
     El_next = SparseLeftTensor(nothing, sz[2])

     # TODO add multi-processing version
     for j in 1:sz[2]
          @floop GlobalThreadsExecutors for i in filter(x -> !isnothing(obj[2][si][x, j]) && !isnothing(obj.El[si][x]), 1:sz[1])
               El = _pushright(obj.El[si][i], obj[1][si], obj[2][si][i, j], obj[3][si]; sparse=true)
               @reduce() do (El_cum = nothing; El)
                    El_cum = axpy!(true, El, El_cum)
               end
          end
          El_next[j] = El_cum
     end

     obj.El[si+1] = El_next

     obj.Center[1] += 1
     return obj
end

function _pushright(El::LocalLeftTensor{2}, A::AdjointMPSTensor{3}, B::MPSTensor{3}; kwargs...)
     if rank(A, 1) == 1
          @tensor tmp[d; e] := (El.A[a b] * A.A[d a c]) * B.A[b c e]
     else
          @tensor tmp[d; e] := (El.A[a b] * A.A[c d a]) * B.A[b c e]
     end
     return LocalLeftTensor(tmp, El.tag)
end

function _pushright(El::LocalLeftTensor{2}, A::AdjointMPSTensor{3}, H::IdentityOperator, B::MPSTensor{3}; kwargs...)
     return _pushright(El, A, B) * H.strength
end

function _pushright(El::LocalLeftTensor{2}, A::AdjointMPSTensor{3}, H::LocalOperator{1, 1}, B::MPSTensor{3}; kwargs...)
     if rank(A, 1) == 1
          @tensor tmp[a; f] := ((A.A[a b c] * H.A[c e]) * El.A[b d]) * B.A[d e f]
     else
          @tensor tmp[a; f] := ((A.A[c a b] * H.A[c e]) * El.A[b d]) * B.A[d e f]
     end
     return LocalLeftTensor(tmp * H.strength, El.tag)
end

function _pushright(El::LocalLeftTensor{2}, A::AdjointMPSTensor{3}, H::LocalOperator{1,2}, B::MPSTensor{3}; kwargs...)
     # χ < d in most sparse cases
     if get(kwargs, :sparse, true)
          # D^3d + D^2d^2χ + D^3dχ
          if rank(A, 1) == 1
               @tensor tmp[a; f g] := ((A.A[a b c] * El.A[b d]) * H.A[c e f]) * B.A[d e g]
          else
               @tensor tmp[a; f g] := ((A.A[c a b] * El.A[b d]) * H.A[c e f]) * B.A[d e g]
          end
     else
          # D^3d + D^3d^2 + D^2d^2χ
          if rank(A, 1) == 1
               @tensor tmp[a; f g] := ((A.A[a b c] * El.A[b d]) * B.A[d e g]) * H.A[c e f]
          else
               @tensor tmp[a; f g] :=  ((A.A[c a b] * El.A[b d]) * B.A[d e g]) * H.A[c e f]
          end
     end
     return LocalLeftTensor(tmp * H.strength, (El.tag[1], H.tag[2][2], El.tag[2]))
end

function _pushright(El::LocalLeftTensor{3}, A::AdjointMPSTensor{3}, H::LocalOperator{2, 1}, B::MPSTensor{3}; kwargs...)
     # contraction order of El and H does not affect complexity
     # D^3dχ + D^2d^2χ + D^3d
     if rank(A, 1) == 1
          @tensor tmp[a;g] := ((A.A[a b c] * El.A[b d e]) * H.A[d c f]) * B.A[e f g]
     else 
          @tensor tmp[a;g] := ((A.A[c a b] * El.A[b d e]) * H.A[d c f]) * B.A[e f g]
     end
     return LocalLeftTensor(tmp * H.strength, (El.tag[1], El.tag[3]))
end

function _pushright(El::LocalLeftTensor{3}, A::AdjointMPSTensor{3}, H::LocalOperator{1,1}, B::MPSTensor{3}; kwargs...)
     # D^2d^2 + D^3dχ + D^3dχ
     if rank(A, 1) == 1
          @tensor tmp[a; d g] := ((A.A[a b c] * H.A[c f]) * El.A[b d e]) * B.A[e f g]
     else 
          @tensor tmp[a; d g] := ((A.A[c a b] * H.A[c f]) * El.A[b d e]) * B.A[e f g]
     end
     return LocalLeftTensor(tmp * H.strength, El.tag)
end

function _pushright(El::LocalLeftTensor{3}, A::AdjointMPSTensor{3}, H::IdentityOperator, B::MPSTensor{3}; kwargs...)
     # D^2d^2 + D^3dχ + D^3dχ
     if rank(A, 1) == 1
          @tensor tmp[a; d g] := (A.A[a b f] * El.A[b d e]) * B.A[e f g]
     else 
          @tensor tmp[a; d g] := (A.A[f a b] * El.A[b d e]) * B.A[e f g]
     end
     return LocalLeftTensor(tmp * H.strength, El.tag)
end

function _pushright(El::LocalLeftTensor{3}, A::AdjointMPSTensor{3}, H::LocalOperator{2, 2}, B::MPSTensor{3}; kwargs...)
     if rank(A, 1) == 1
          @tensor tmp[d; g h] := ((A.A[d a e] * El.A[a b c]) * H.A[b e f g]) * B.A[c f h]
     else
          @tensor tmp[d; g h] := ((A.A[e d a] * El.A[a b c]) * H.A[b e f g]) * B.A[c f h]
     end
     return LocalLeftTensor(tmp * H.strength, (El.tag[1], H.tag[2][2], El.tag[3]))
end

function _pushright(El::LocalLeftTensor{3}, A::AdjointMPSTensor{3}, H::LocalOperator{1, 3}, B::MPSTensor{3}; kwargs...)
     if rank(A, 1) == 1
          @tensor tmp[d; b g i h] :=  ((A.A[d a e] * El.A[a b c]) * H.A[e f g i]) * B.A[c f h]
     else
          @tensor tmp[d; b g i h] :=  ((A.A[e d a] * El.A[a b c]) * H.A[e f g i]) * B.A[c f h]
     end
     return LocalLeftTensor(tmp * H.strength, (El.tag[1:2]..., H.tag[2][2:3]..., El.tag[3]))
end

function _pushright(El::LocalLeftTensor{5}, A::AdjointMPSTensor{3}, H::LocalOperator{3, 1}, B::MPSTensor{3}; kwargs...)
     # match tags
     if El.tag[2:3] == H.tag[1][1:2]
          if rank(A, 1) == 1
               @tensor tmp[a; f i] := ((A.A[a b c] * H.A[d e c h]) * El.A[b d e f g]) * B.A[g h i]
          else
               @tensor tmp[a; f i] := ((A.A[c a b] * H.A[d e c h]) * El.A[b d e f g]) * B.A[g h i]
          end
          return LocalLeftTensor(tmp * H.strength, (El.tag[1], El.tag[4], El.tag[5]))
     elseif El.tag[2:3] == reverse(H.tag[1][1:2])
          if rank(A, 1) == 1
               @tensor tmp[a; f i] := ((A.A[a b c] * H.A[e d c h]) * El.A[b d e f g]) * B.A[g h i]
          else
               @tensor tmp[a; f i] := ((A.A[c a b] * H.A[e d c h]) * El.A[b d e f g]) * B.A[g h i]
          end
          return LocalLeftTensor(tmp * H.strength, (El.tag[1], El.tag[4], El.tag[5]))
     elseif El.tag[[2, 4]] == H.tag[1][1:2]
          if rank(A, 1) == 1
               @tensor tmp[a; e i] := ((A.A[a b c] * H.A[d f c h]) * El.A[b d e f g]) * B.A[g h i]
          else
               @tensor tmp[a; e i] := ((A.A[c a b] * H.A[d f c h]) * El.A[b d e f g]) * B.A[g h i]
          end
          return LocalLeftTensor(tmp * H.strength, (El.tag[1], El.tag[3], El.tag[5]))
     elseif El.tag[[2, 4]] == reverse(H.tag[1][1:2])
          if rank(A, 1) == 1
               @tensor tmp[a; e i] := ((A.A[a b c] * H.A[f d c h]) * El.A[b d e f g]) * B.A[g h i]
          else
               @tensor tmp[a; e i] := ((A.A[c a b] * H.A[f d c h]) * El.A[b d e f g]) * B.A[g h i]
          end
          return LocalLeftTensor(tmp * H.strength, (El.tag[1], El.tag[3], El.tag[5]))
     else
          @show El.tag
          @show H.tag
          error("please add method!")
     end
     
end

function _pushright(El::LocalLeftTensor{2}, A::AdjointMPSTensor{3}, H::LocalOperator{1, 3}, B::MPSTensor{3}; kwargs...)
     if rank(A, 1) == 1
          @tensor tmp[a; f g h] := ((A.A[a b c] * El.A[b d]) * H.A[c e f g]) * B.A[d e h]
     else
          @tensor tmp[a; f g h] := ((A.A[c a b] * El.A[b d]) * H.A[c e f g]) * B.A[d e h]
     end
     return LocalLeftTensor(tmp * H.strength, (El.tag[1], H.tag[2][2:3]..., El.tag[2]))
end

function _pushright(El::LocalLeftTensor{4}, A::AdjointMPSTensor{3}, H::LocalOperator{1, 2}, B::MPSTensor{3}; kwargs...)
     if rank(A, 1) == 1
          @tensor tmp[a; d e h i] := ((A.A[a b c] * H.A[c g h]) * El.A[b d e f]) * B.A[f g i]
     else
          @tensor tmp[a; d e h i] := ((A.A[c a b] * H.A[c g h]) * El.A[b d e f]) * B.A[f g i]
     end
     return LocalLeftTensor(tmp * H.strength, (El.tag[1:3]..., H.tag[2][2], El.tag[4]))
end

function _pushright(El::LocalLeftTensor{5}, A::AdjointMPSTensor{3}, H::LocalOperator{2, 1}, B::MPSTensor{3}; kwargs...)
    
     if El.tag[2] == H.tag[1][1]
          if rank(A, 1) == 1
               @tensor tmp[a; e f i] := ((A.A[a b c] * H.A[d c h]) * El.A[b d e f g]) * B.A[g h i]
          else
               @tensor tmp[a; e f i] := ((A.A[c a b] * H.A[d c h]) * El.A[b d e f g]) * B.A[g h i]
          end
          return LocalLeftTensor(tmp * H.strength, (El.tag[1], El.tag[3:5]...))
     elseif El.tag[3] == H.tag[1][1]
          if rank(A, 1) == 1
               @tensor tmp[a; d f i] := ((A.A[a b c] * H.A[e c h]) * El.A[b d e f g]) * B.A[g h i]
          else
               @tensor tmp[a; d f i] := ((A.A[c a b] * H.A[e c h]) * El.A[b d e f g]) * B.A[g h i]
          end
          return LocalLeftTensor(tmp * H.strength, (El.tag[1:2]..., El.tag[4:5]...))
     elseif El.tag[4] == H.tag[1][1]
          if rank(A, 1) == 1
               @tensor tmp[a; d e i] := ((A.A[a b c] * H.A[f c h]) * El.A[b d e f g]) * B.A[g h i]
          else
               @tensor tmp[a; d e i] := ((A.A[c a b] * H.A[f c h]) * El.A[b d e f g]) * B.A[g h i]
          end
          return LocalLeftTensor(tmp * H.strength, (El.tag[1:3]..., El.tag[5]))
     else
          @show El.tag
          @show H.tag
          error("please add method!")
     end
end

function _pushright(El::LocalLeftTensor{4}, A::AdjointMPSTensor{3}, H::LocalOperator{3, 1}, B::MPSTensor{3}; kwargs...)
     if El.tag[2:3] == H.tag[1][1:2]
          if rank(A, 1) == 1
               @tensor tmp[a; h] := ((A.A[a b c] * El.A[b d e f]) * H.A[d e c g]) * B.A[f g h]
          else
               @tensor tmp[a; h] := ((A.A[c a b] * El.A[b d e f]) * H.A[d e c g]) * B.A[f g h]
          end
          return LocalLeftTensor(tmp * H.strength, (El.tag[1], El.tag[4]))
     elseif El.tag[2:3] == reverse(H.tag[1][1:2])
          if rank(A, 1) == 1
               @tensor tmp[a; h] := ((A.A[a b c] * El.A[b d e f]) * H.A[e d c g]) * B.A[f g h]
          else
               @tensor tmp[a; h] := ((A.A[c a b] * El.A[b d e f]) * H.A[e d c g]) * B.A[f g h]
          end
          return LocalLeftTensor(tmp * H.strength, (El.tag[1], El.tag[4]))
     else
          @show El.tag
          @show H.tag
          error("please add method!")
     end 

end

function _pushright(El::LocalLeftTensor{4}, A::AdjointMPSTensor{3}, H::LocalOperator{2, 1}, B::MPSTensor{3}; kwargs...)
     if El.tag[2] == H.tag[1][1]
          if rank(A, 1) == 1
               @tensor tmp[a; e i] := ((A.A[a b c] * H.A[d c h]) * El.A[b d e g]) * B.A[g h i]
          else
               @tensor tmp[a; e i] := ((A.A[c a b] * H.A[d c h]) * El.A[b d e g]) * B.A[g h i]
          end
          return LocalLeftTensor(tmp * H.strength, (El.tag[1], El.tag[3:4]...))
     elseif El.tag[3] == H.tag[1][1]
          if rank(A, 1) == 1
               @tensor tmp[a; d i] := ((A.A[a b c] * H.A[e c h]) * El.A[b d e g]) * B.A[g h i]
          else
               @tensor tmp[a; d i] := ((A.A[c a b] * H.A[e c h]) * El.A[b d e g]) * B.A[g h i]
          end
          return LocalLeftTensor(tmp * H.strength, (El.tag[1:2]..., El.tag[4]))
     else
          @show El.tag
          @show H.tag
          error("please add method!")
     end
end

function _pushright(El::LocalLeftTensor{3}, A::AdjointMPSTensor{3}, H::LocalOperator{1, 2}, B::MPSTensor{3}; kwargs...)
     if rank(A, 1) == 1
          @tensor tmp[a; d g h] := ((A.A[a b c] * El.A[b d e]) * H.A[c f g]) * B.A[e f h]
     else
          @tensor tmp[a; d g h] := ((A.A[c a b] * El.A[b d e]) * H.A[c f g]) * B.A[e f h]
     end
     return LocalLeftTensor(tmp * H.strength, (El.tag[1:2]..., H.tag[2][2], El.tag[3]))
end

function _pushright(El::LocalLeftTensor{4}, A::AdjointMPSTensor{3}, H::LocalOperator{1, 1}, B::MPSTensor{3}; kwargs...)
     if rank(A, 1) == 1
          @tensor tmp[a; d e h] := ((A.A[a b c] * H.A[c g]) * El.A[b d e f]) * B.A[f g h]
     else
          @tensor tmp[a; d e h] := ((A.A[c a b] * H.A[c g]) * El.A[b d e f]) * B.A[f g h]
     end
     return LocalLeftTensor(tmp * H.strength, El.tag)
end

function _pushright(El::LocalLeftTensor{5}, A::AdjointMPSTensor{3}, H::IdentityOperator, B::MPSTensor{3}; kwargs...)
     if rank(A, 1) == 1
          @tensor tmp[a; d e f h] := (A.A[a b c] * El.A[b d e f g]) * B.A[g c h]
     else
          @tensor tmp[a; d e f h] := (A.A[c a b] * El.A[b d e f g]) * B.A[g c h]
     end
     return LocalLeftTensor(tmp * H.strength, El.tag)
end



