# https://people.csail.mit.edu/plaat/mtdf.html#abmem

#                                       depth lower upper
#TranspositionTable = Dict{String, Tuple{Int,Float64,Float64}}
AlphaBetaMemory = Dict{String, Tuple{Int,UInt8,Float64}}

const EXACT = 0x0
const UPPER = 0x1
const LOWER = 0x2

function key(node::Node)::String
    key = ""
    if node.move != (0x00, 0x00, 0x00)
        while node.parent != nothing
            key = string(node.move) * " " * key
            node = node.parent
        end
    end
    return key
end

function AlphaBetaWithMemory(beth::Beth, node::Node, depth::Int, α::Float64, β::Float64, white::Bool, tt::AlphaBetaMemory)
    value = 0.
    _α = α # store
    _β = β # store

    beth.n_explored_nodes += 1
    _white, = restore_board_position(beth, node)
    @assert _white == white

    # transposition table look up
    if haskey(tt, key(node))
        d, flag, value = tt[key(node)]
        if flag == EXACT
            node.score = value
            return value
        elseif flag == LOWER
            α = max(α, value)
        elseif flag == UPPER
            β = min(β, value)
        end

        if α ≥ β
            node.score = value
            return value
        end
    end


    if depth == 0
        beth.n_leafes += 1
        value, = beth.value_heuristic(beth._board, white)
        node.score = value
    else
        ms = get_moves(beth._board, white)
        ranked_moves = beth.rank_heuristic(beth._board, white, ms)
        sort!(ranked_moves, rev=white) # try to choose best moves first

        if white
            value = -Inf
            for (i,(prescore, m)) in enumerate(ranked_moves)
                child = Node(move=m, parent=node, score=prescore, visits=0)
                push!(node.children, child)

                value = max(value, AlphaBetaWithMemory(beth, child, depth-1, α, β, false, tt))
                α = max(α, value)
                α ≥ β && break ## β cutoff
            end
            node.score = value
        else
            value = Inf
            for (i,(prescore, m)) in enumerate(ranked_moves)
                child = Node(move=m, parent=node, score=prescore, visits=0)
                push!(node.children, child)

                value = min(value, AlphaBetaWithMemory(beth, child, depth-1, α, β, true, tt))
                β = min(β, value)
                β ≤ α && break # α cutoff
            end
            node.score = value
        end
    end

    if value ≤ _α
        # Fail low result implies an upper bound
        tt[key(node)] = (depth, UPPER, value)
    elseif β ≤ value
        # Fail high result implies a lower bound
        tt[key(node)] = (depth, LOWER, value)
    else
        # Found an accurate minimax value - will not occur if called with zero window (α = β-
        tt[key(node)] = (depth, EXACT, value)
    end

    return value
end

function alphabeta_search(beth::Beth; board=beth.board, white=beth.white, verbose=true, lower=-Inf, upper=Inf, mem = AlphaBetaMemory())
    beth.board = board
    beth.white = white
    beth.n_leafes = 0
    beth.n_explored_nodes = 0

    root = Node()

    v,t = @timed AlphaBetaWithMemory(beth, root, depth, lower, upper, white, mem)

    verbose && @info(@sprintf "%d nodes (%d leafes) explored in %.4f seconds (%.2f/s)." beth.n_explored_nodes beth.n_leafes t (beth.n_explored_nodes/t) )

    return root, mem
end


function MTDF(beth::Beth; board=beth.board, white=beth.white, guess::Float64, depth::Integer)
    beth.board = board
    beth.white = white
    beth.n_leafes = 0
    beth.n_explored_nodes = 0

    value = guess
    upper = Inf
    lower = -Inf

    mem = AlphaBetaMemory()
    root = Node()
    _,t = @timed while true
        β = value == lower ? value + 0.1 : value
        root = Node()
        value = AlphaBetaWithMemory(beth, root, depth, β-0.1, β, white, mem)
        if value < β
            upper = value
        else
            lower = value
        end

        #@info("value: $value, alpha: $(β-1), beta: $β, lower: $lower, $upper")

        if lower ≥ upper
            break
        end
    end

    @info(@sprintf "%d nodes (%d leafes) explored in %.4f seconds (%.2f/s)." beth.n_explored_nodes beth.n_leafes t (beth.n_explored_nodes/t) )


    return root
end

function IMTDF(beth::Beth; board=beth.board, white=beth.white, max_depth::Int)
    guesses = [0.]
    for depth in 2:2:max_depth
        guess = guesses[end]
        @info "Depth: $depth, guess: $guess"
        @time root = MTDF(beth, board=board, white=white, guess=guess, depth=depth)
        push!(guesses, root.score)
    end
    return guesses[end]
end

function distributed_search(beth::Beth; board, white)
    ms = get_moves(board, white)
    ranked_moves = beth.rank_heuristic(board, white, ms)
    sort!(ranked_moves, rev=white)

    for (i,(prescore, rm)) in enumerate(ranked_moves)
        _board = deepcopy(board)
        move!(_board, white, rm[1], rm[2], rm[3])
        v = minimax_search(beth, board=_board, white=!white, verbose=false).score
        @info(@sprintf "%d: %s prescore: %.2f, value: %.2f" i rm prescore v)
    end

end

pz = rush_20_12_13[5]
print_puzzle(pz)

bfs = [Inf,Inf,Inf,Inf,Inf,Inf]
depth = 5
beth = Beth(value_heuristic=beth_eval, rank_heuristic=beth_rank_moves, search_args=Dict("depth"=>depth, "branching_factors"=>bfs))

root = minimax_search(beth, board=deepcopy(pz.board), white=pz.white_to_move)

print_tree(root["Rd7d4"], max_depth=1, white=pz.white_to_move, has_to_have_children=false)

distributed_search(beth, board=deepcopy(pz.board), white=pz.white_to_move)


root, mem = alphabeta_search(beth, board=deepcopy(pz.board), white=pz.white_to_move)

root, mem = alphabeta_search(beth, board=deepcopy(pz.board), white=pz.white_to_move, mem=mem)

root = MTDF(beth,  board=deepcopy(pz.board), white=pz.white_to_move, guess=0., depth=4)

IMTDF(beth, board=deepcopy(pz.board), white=pz.white_to_move, max_depth=8)

1. B: e3-d4, score: 4.4000, visits: 0, 2 children
2. K: h3-h4, score: 4.4000, visits: 0, 1 children
3. K: h3-h2, score: 4.4000, visits: 0, 1 children
4. R: d7-d8, score: 4.4000, visits: 0, 1 children
5. R: d7-e7, score: 4.4000, visits: 0, 1 children
6. R: d7-c7, score: 4.4000, visits: 0, 1 children
7. R: d7-b7, score: 4.4000, visits: 0, 1 children
8. R: d7-a7, score: 4.4000, visits: 0, 1 children
9. R: d7-d2, score: 4.4000, visits: 0, 1 children
10. R: d7-d1, score: 4.4000, visits: 0, 1 children
11. B: e3-a7, score: 4.4000, visits: 0, 1 children
12. B: e3-h6, score: 4.4000, visits: 0, 1 children
13. B: e3-b6, score: 4.4000, visits: 0, 1 children
14. B: e3-c5, score: 4.4000, visits: 0, 1 children
15. B: e3-d2, score: 4.4000, visits: 0, 1 children
16. P: b2-b3, score: 4.4000, visits: 0, 1 children
17. B: e3-g1, score: 4.3000, visits: 0, 1 children
18. B: e3-c1, score: 4.3000, visits: 0, 1 children
19. P: a3-a4, score: 3.7000, visits: 0, 1 children
20. P: c3-c4, score: 3.6000, visits: 0, 1 children
21. P: b2-b4, score: 3.3000, visits: 0, 1 children
22. R: d7-d4, score: -0.5000, visits: 0, 2 children
23. R: d7-d6, score: -0.5000, visits: 0, 1 children
24. R: d7-d3, score: -0.6000, visits: 0, 1 children
25. B: e3-g5, score: -0.6000, visits: 0, 1 children
26. B: e3-f2, score: -0.6000, visits: 0, 2 children
27. B: e3-f4, score: -3.4000, visits: 0, 1 children
28. R: d7-f7, score: -4.2000, visits: 0, 3 children
29. R: d7-d5, score: -5.6000, visits: 0, 4 children
""a


#=
α = β - 1

β - α = β - (β - 1) = 1

g > α && g < β => β - 1 < g < β


0. Root Node, score: 2.1000, visits: 0, 41 children
​   1. B: c3-d4, score: 2.1000, visits: 0, 37 children
    2. R: c1-c2, score: 1.9000, visits: 0, 1 children
    3. R: e1-e3, score: 0.0000, visits: 0, 1 children
    4. B: b5-e2, score: -0.4000, visits: 0, 2 children
    5. B: b5-f1, score: -0.5000, visits: 0, 2 children
    6. B: b5-d7, score: -1.0000, visits: 0, 37 children
    7. B: c3-b4, score: -1.0000, visits: 0, 2 children
    8. Q: d2-d5, score: -1.1000, visits: 0, 1 children
    9. Q: d2-h6, score: -1.9000, visits: 0, 1 children
    10. B: b5-c4, score: -2.0000, visits: 0, 2 children
    11. N: f3-d4, score: -2.1000, visits: 0, 2 children
    12. Q: d2-g5, score: -2.1000, visits: 0, 2 children
    13. Q: d2-f4, score: -2.1000, visits: 0, 1 children
    14. Q: d2-d3, score: -2.1000, visits: 0, 1 children
    15. Q: d2-e2, score: -2.1000, visits: 0, 2 children
    16. Q: d2-b2, score: -2.1000, visits: 0, 2 children
    17. Q: d2-d1, score: -2.1000, visits: 0, 2 children
    18. R: e1-e2, score: -2.1000, visits: 0, 2 children
    19. R: e1-f1, score: -2.1000, visits: 0, 2 children
    20. R: e1-d1, score: -2.1000, visits: 0, 2 children
    21. R: c1-d1, score: -2.1000, visits: 0, 2 children
    22. R: c1-b1, score: -2.1000, visits: 0, 2 children
    23. R: c1-a1, score: -2.1000, visits: 0, 2 children
    24. N: f3-g5, score: -2.1000, visits: 0, 2 children
    25. N: f3-h4, score: -2.1000, visits: 0, 2 children
    26. B: b5-c6, score: -2.1000, visits: 0, 2 children
    27. B: b5-d3, score: -2.1000, visits: 0, 2 children
    28. B: c3-b2, score: -2.1000, visits: 0, 2 children
    29. B: c3-a1, score: -2.1000, visits: 0, 2 children
    30. P: h2-h4, score: -2.1000, visits: 0, 2 children
    31. P: h2-h3, score: -2.1000, visits: 0, 2 children
    32. P: g2-g4, score: -2.1000, visits: 0, 2 children
    33. P: g2-g3, score: -2.1000, visits: 0, 2 children
    34. K: g1-f1, score: -2.3000, visits: 0, 1 children
    35. K: g1-h1, score: -2.6000, visits: 0, 1 children
    36. B: b5-a6, score: -3.9000, visits: 0, 2 children
    37. Q: d2-d4, score: -3.9000, visits: 0, 1 children
    38. R: e1-e4, score: -4.0000, visits: 0, 2 children
    39. Q: d2-e3, score: -4.0000, visits: 0, 1 children
    40. Q: d2-c2, score: -8.1000, visits: 0, 2 children
    41. Q: d2-a2, score: -8.1000, visits: 0, 2 children


=#
