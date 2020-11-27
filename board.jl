struct Board
    position::BitArray{3}
    can_en_passant::BitArray{2}
    can_castle::BitArray{2} # first index player second LEFT/RIGHT
    # rows are ranks
    # columns are files
    # c2 -> (2,c) -> (2, 3)

    # TODO: validate by xoring
    function Board(start=true)
        position = falses(8, 8, 8)
        can_en_passant = falses(2, 8)
        can_castle = trues(2,2)
        if start
            position[[2,7],:,PAWN] .= 1
            position[[1,8], [3,6], BISHOP] .= 1
            position[[1,8], [2,7], KNIGHT] .= 1
            position[[1,8], [1,8], ROOK] .= 1
            position[[1,8], 4, QUEEN] .= 1 # d für dame
            position[[1,8], 5, KING] .= 1
            position[[1,2], :, WHITE] .= 1
            position[[7,8], :, BLACK] .= 1
        end
        return new(position, can_en_passant, can_castle)
    end
end

function is_valid(board::Board)
    A = sum(board.position[:,:,1:6], dims=3) .== 1
    B = board.position[:,:,WHITE]
    C = board.position[:,:,BLACK]
    #println(A)
    #println(B)
    #println(C)
    all(xor.(A, B) .== C) && all(xor.(A, C) .== B)
end

import Base.getindex
function Base.getindex(b::Board, I...)
    Base.getindex(b.position, I...)
end

# import Base.setindex!
# function Base.setindex!(b::Board, v, I...)
#     #println("set: ", v, ", ", I)
#     Base.setindex!(b.position, v, I...)
# end




#=
    r1, f1: current field
    r2, f2: target field
    piece: 1-6
=#
function move!(board::Board, white::Bool, piece::Piece, r1::Int, f1::Int, r2::Int, f2::Int)
    player = 7 + !white
    opponent = 7 + white
    @assert board[r1,f1,player] "No piece for player at $r1, $(f1)!"
    @assert !board[r2,f2,player] "Player tried to capture own piece! $(SYMBOLS[1,piece]) $(field(r1,f1)) $(field(r2,f2))"
    @assert board[r1,f1,piece] "Piece not at field! $(SYMBOLS[1,piece]) $(field(r1,f1)) $(field(r2,f2))"

    captured = nothing
    en_passant = copy(board.can_en_passant)
    castle = nothing

    if board[r2,f2,opponent]
        # remove captured piece
        captured = findfirst(board[r2,f2,1:6])
        board.position[r2,f2,captured] = false
        board.position[r2,f2,opponent] = false
    end


    board.position[r1,f1,piece] = false
    board.position[r2,f2,piece] = true

    board.position[r1,f1,player] = false
    board.position[r2,f2,player] = true

    # handle en passant
    if piece == PAWN && abs((r1 - r2) == 2)
        board.can_en_passant[white+1, f1] = true
    end
    board.can_en_passant[white+1, :] .= false

    # handle caslte
    if piece == KING
        bcastle = board.can_castle[white+1,:]
        board.can_castle[white+1,:] .= false
        if f2 - f1 == 2 # castle short
            board.position[r1, 8, ROOK] = false
            board.position[r1, 6, ROOK] = true

            board.position[r1, 8, player] = false
            board.position[r1, 6, player] = true

            castle = (2, bcastle)
        elseif f1 - f2 == 2 # castle long
            board.position[r1, 1, ROOK] = false
            board.position[r1, 4, ROOK] = true

            board.position[r1, 1, player] = false
            board.position[r1, 4, player] = true

            castle = (1, bcastle)
        end
    elseif piece == ROOK
        if f1 == 1
            board.can_castle[white+1,1] = false
            castle = (white+1, 1)
        elseif f2 == 8
            board.can_castle[white+1,2] = false
            castle = (white+1, 2)
        end
    end


    return captured, en_passant, castle
end

function undo!(board::Board, white::Bool, piece::Piece, r1::Int, f1::Int, r2::Int, f2::Int, captured, en_passant, castle)
    player = 7 + !white
    opponent = 7 + white

    board.position[r1,f1,piece] = true
    board.position[r2,f2,piece] = false

    board.position[r1,f1,player] = true
    board.position[r2,f2,player] = false

    if captured != nothing
        board.position[r2,f2,opponent] = true
        board.position[r2,f2,captured] = true
    end

    if en_passant != nothing
        board.can_en_passant .= en_passant
    end

    if castle != nothing
        if piece == KING
            i, bcastle = castle
            if i == 1 # long castle
                board.position[r1, 1, ROOK] = true
                board.position[r1, 4, ROOK] = false

                board.position[r1, 1, player] = true
                board.position[r1, 4, player] = false

            end

            if i == 2 # short castle
                board.position[r1, 8, ROOK] = true
                board.position[r1, 6, ROOK] = false

                board.position[r1, 8, player] = true
                board.position[r1, 6, player] = false
            end

            board.can_castle[white+1, :] = bcastle
        end

        if piece == ROOK
            if castle isa Tuple
                board.can_castle[castle...] = true
            end
        end
    end
end

#=
    rf1: current field as per FIELDS
    rf2: target field as per FIELDS
    p: piece as per PIECES
=#
function move!(board::Board, white::Bool, p::Piece, rf1::FieldSymbol, rf2::FieldSymbol)
    # moves are assumed to be valid
    move!(board, white, p, cartesian(FIELDS[rf1])..., cartesian(FIELDS[rf2])...)
end

function undo!(board::Board, white::Bool, p::Piece, rf1::FieldSymbol, rf2::FieldSymbol, captured, can_en_passant, can_castle)
    undo!(board, white, p, cartesian(FIELDS[rf1])..., cartesian(FIELDS[rf2])..., captured, can_en_passant, can_castle)
end

function move!(board::Board, white::Bool, p::PieceSymbol, rf1::Field, rf2::Field; verbose=false)
    # TODO: check if move is valid

    captured, can_en_passant, can_castle = move!(board, white, PIECES[p], cartesian(rf1)..., cartesian(rf2)...)
    if verbose
        captured != nothing && println("Captured $(SYMBOLS[1,captured]).")
        opponent = 7 + white
        check = is_check(board, opponent)
        n_moves = length(get_moves(board, !white))
        (check && n_moves > 0) && println("Check!")
        (check && n_moves == 0) && println("Checkmate!")
        (!check && n_moves == 0) && println("Stalemate!")
    end
    return captured, can_en_passant, can_castle
end

function undo!(board::Board, white::Bool, p::PieceSymbol, rf1::Field, rf2::Field, captured, cen_passant, castle)
    undo!(board, white, PIECES[p], cartesian(rf1)..., cartesian(rf2)..., captured, en_passant, castle)
end

import Base.show
function Base.show(io::IO, board::Board)
    cols = [:white, :blue]

    println(io, "Chess Board")
    for rank in 8:-1:1
        print(io,"$rank ")
        for file in 1:8
            s = "⋅"
            if sum(board[rank,file,:]) != 0
                piece = argmax(board[rank,file,1:6])
                if any(board[rank,file,7:8])
                    si = findfirst(board[rank,file,7:8])
                    s = SYMBOLS[1, piece]

                    printstyled(io, "$s ", color=cols[si], bold=true)
                    continue
                end
            end

            printstyled(io,"$s ", bold=true)
        end
        print(io,"\n")
    end
    println(io,"  a b c d e f g h")
end

function print_board(board::Board; highlight=nothing, player=:white)
    cols = [:white, :blue]

    highlight_fields = []
    if highlight != nothing && player != nothing
        p = PIECES[highlight[1]]
        rf = symbol(highlight[2:3])
        moves = get_moves(board, player==:white)
        highlight_moves = filter(m -> m[1] == p && m[2] == rf, moves)
        highlight_fields = map(m -> cartesian(field(m[3])), highlight_moves)
    end

    println("Chess Board")
    for rank in 8:-1:1
        printstyled("$rank ", color=13)
        for file in 1:8
            s = "•" #"⦿" # "⋅"
            if sum(board[rank,file,:]) != 0
                piece = argmax(board[rank,file,1:6])
                if any(board[rank,file,7:8])
                    si = findfirst(board[rank,file,7:8])
                    s = SYMBOLS[1, piece]

                    col = cols[si]
                    if (rank, file) in highlight_fields
                        col = :red
                    end

                    printstyled("$s ", color=col, bold=true)
                    continue
                end
            end
            col = 8
            if (rank, file) in highlight_fields
                col = :green
            end

            printstyled("$s ", bold=true, color=col)
        end
        print("\n")
    end
    printstyled("  a b c d e f g h", color=13)
end
