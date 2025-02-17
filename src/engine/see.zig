const std = @import("std");
const types = @import("../chess/types.zig");
const tables = @import("../chess/tables.zig");
const position = @import("../chess/position.zig");
const hce = @import("hce.zig");
const movepick = @import("movepick.zig");

pub const SeeWeight = [_]movepick.SortScore{ 96, 323, 323, 551, 864, 20000 };

pub fn see_score(pos: *position.Position, move: types.Move) movepick.SortScore {
    var max_depth: usize = 0;
    var defenders: types.Bitboard = 0;
    var piece_bb: types.Bitboard = 0;

    var to_sq = move.get_to();
    var all_pieces = pos.all_pieces(types.Color.White) | pos.all_pieces(types.Color.Black);
    var gains: [16]movepick.SortScore = undefined;
    var opp = pos.turn.invert();
    var blockers = all_pieces & ~types.SquareIndexBB[move.to];

    gains[0] = SeeWeight[pos.mailbox[move.to].piece_type().index()];
    var last_piece_pts = SeeWeight[pos.mailbox[move.from].piece_type().index()];

    var depth: usize = 1;
    outer: while (depth < gains.len) : (depth += 1) {
        gains[depth] = last_piece_pts - gains[depth - 1];
        if (opp == types.Color.White) {
            defenders = pos.all_pieces(types.Color.White) & blockers;
        } else {
            defenders = pos.all_pieces(types.Color.Black) & blockers;
        }
        var pt = types.PieceType.Pawn.index();
        var ending = types.PieceType.King.index();
        while (pt <= ending) : (pt += 1) {
            last_piece_pts = SeeWeight[pt];
            piece_bb = (if (pt == 0) (if (opp == types.Color.White) tables.get_pawn_attacks(types.Color.Black, to_sq) else tables.get_pawn_attacks(types.Color.White, to_sq)) else (tables.get_attacks(@intToEnum(types.PieceType, pt), to_sq, blockers))) & defenders & (pos.piece_bitboards[pt] | pos.piece_bitboards[pt + 8]);
            if (piece_bb != 0) {
                blockers &= ~(types.SquareIndexBB[@intCast(usize, types.lsb(piece_bb))]);
                opp = opp.invert();
                continue :outer;
            }
        }

        max_depth = depth;
        break;
    }

    depth = max_depth - 1;
    while (depth >= 1) : (depth -= 1) {
        gains[depth - 1] = -@max(-gains[depth - 1], gains[depth]);
    }

    return gains[0];
}

// Logic https://github.com/TerjeKir/weiss
pub fn see_threshold(pos: *position.Position, move: types.Move, threshold: hce.Score) bool {
    var from = move.from;
    var to = move.to;
    var attacker = pos.mailbox[from].piece_type().index();
    var victim = pos.mailbox[to].piece_type().index();
    var swap = SeeWeight[victim] - threshold;
    if (swap < 0) {
        return false;
    }
    swap -= SeeWeight[attacker];
    if (swap >= 0) {
        return true;
    }

    var all = pos.all_pieces(types.Color.White) | pos.all_pieces(types.Color.Black);

    var occ = (all ^ types.SquareIndexBB[from]) | types.SquareIndexBB[to];
    var attackers = (pos.attackers_from(types.Color.White, @intToEnum(types.Square, to), occ) | pos.attackers_from(types.Color.Black, @intToEnum(types.Square, to), occ)) & occ;

    var bishops = pos.diagonal_sliders(types.Color.White) | pos.diagonal_sliders(types.Color.Black);
    var rooks = pos.orthogonal_sliders(types.Color.White) | pos.orthogonal_sliders(types.Color.Black);

    var stm = pos.mailbox[from].color().invert();

    while (true) {
        attackers &= occ;
        var my_attackers = attackers;
        if (stm == types.Color.White) {
            my_attackers &= pos.all_pieces(types.Color.White);
        } else {
            my_attackers &= pos.all_pieces(types.Color.Black);
        }
        if (my_attackers == 0) {
            break;
        }

        var pt: usize = 0;
        while (pt <= 5) : (pt += 1) {
            if (my_attackers & (pos.piece_bitboards[pt] | pos.piece_bitboards[pt + 8]) != 0) {
                break;
            }
        }

        stm = stm.invert();

        swap = -swap - 1 - SeeWeight[pt];

        if (swap >= 0) {
            if (pt == 5) {
                if (stm == types.Color.White) {
                    if (attackers & pos.all_pieces(types.Color.White) != 0) {
                        stm = stm.invert();
                    }
                } else {
                    if (attackers & pos.all_pieces(types.Color.Black) != 0) {
                        stm = stm.invert();
                    }
                }
            }
            break;
        }

        occ ^= types.SquareIndexBB[@intCast(usize, types.lsb(my_attackers & (pos.piece_bitboards[pt] | pos.piece_bitboards[pt + 8])))];

        if (pt == 0 or pt == 2 or pt == 4) {
            attackers |= tables.get_bishop_attacks(@intToEnum(types.Square, to), occ) & bishops;
        } else if (pt == 3 or pt == 4) {
            attackers |= tables.get_rook_attacks(@intToEnum(types.Square, to), occ) & rooks;
        }
    }

    return stm != pos.mailbox[from].color();
}
