#!/usr/bin/env lua

--[[
lichi - a lua rewrite of michi by Petr Baudis (https://github.com/pasky/michi)
Copyright (C) 2024 gsobell

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.

License of Original code:
michi - Copyright (C) Petr Baudis <pasky@ucw.cz> 2015
MIT licence (i.e. almost public domain)
]]

--[[
Given a board of size NxN (N=9, 19, ...), we represent the position
 as an (N+1)*(N+2) string, with '.' (empty), 'X' (to-play player),
'x' (other player), and whitespace (off-board border to make rules
implementation easier).  Coordinates are just indices in this string.You can simply print(board) when debugging.
]]

N = 13
W = N + 2
function generate_empty(N)
-- empty = "\n".join([(N+1)*' '] + N*[' '+N*'.'] + [(N+2)*' '])
    local result = {}
    table.insert(result, string.rep(" ", N + 1))
    for i = 1, N do
        table.insert(result, " " .. string.rep(".", N))
    end
    table.insert(result, string.rep(" ", N + 2))
    return table.concat(result, "\n")
end
empty =  generate_empty(N)

colstr = 'ABCDEFGHJKLMNOPQRST'
MAX_GAME_LEN = N * N * 3

N_SIMS = 1400
RAVE_EQUIV = 3500
EXPAND_VISITS = 8
PRIOR_EVEN = 10  --should be even number; 0.5 prior
PRIOR_SELFATARI = 10  --negative prior
PRIOR_CAPTURE_ONE = 15
PRIOR_CAPTURE_MANY = 30
PRIOR_PAT3 = 10
PRIOR_LARGEPATTERN = 100  --most moves have relatively small probability
PRIOR_CFG = {24, 22, 8}  --priors for moves in cfg dist. 1, 2, 3
PRIOR_EMPTYAREA = 10
REPORT_PERIOD = 200
PROB_HEURISTIC = {}
PROB_HEURISTIC['capture'] = 0.9
PROB_HEURISTIC['pat3'] = 0.95  -- probability of heuristic suggestions being taken in playout
PROB_SSAREJECT = 0.9  -- probability of rejecting suggested self-atari in playout
PROB_RSAREJECT = 0.5  -- probability of rejecting random self-atari in playout; this is lower than above to allow nakade
RESIGN_THRES = 0.2
FASTPLAY20_THRES = 0.8  -- if at 20% playouts winrate is >this, stop reading
FASTPLAY5_THRES = 0.95  -- if at 5% playouts winrate is >this, stop reading



pat3src = {  -- 3x3 playout patterns; X,O are colors, x,o are their inverses
       {"XOX",  -- hane pattern - enclosing hane
        "...",
        "???"},
       {"XO.",  -- hane pattern - non-cutting hane
        "...",
        "?.?"},
       {"XO?",  -- hane pattern - magari
        "X..",
        "x.?"},
       -- {"XOO",  -- hane pattern - thin hane
       --  "...",
       --  "?.?", "X",  - only for the X player
       {".O.",  -- generic pattern - katatsuke or diagonal attachment; similar to magari
        "X..",
        "..."},
       {"XO?",  -- cut1 pattern (kiri} - unprotected cut
        "O.o",
        "?o?"},
       {"XO?",  -- cut1 pattern (kiri} - peeped cut
        "O.X",
        "???"},
       {"?X?",  -- cut2 pattern (de}
        "O.O",
        "ooo"},
       {"OX?",  -- cut keima
        "o.O",
        "???"},
       {"X.?",  -- side pattern - chase
        "O.?",
        "   "},
       {"OX?",  -- side pattern - block side cut
        "X.O",
        "   "},
       {"?X?",  -- side pattern - block side connection
        "x.O",
        "   "},
       {"?XO",  -- side pattern - sagari
        "x.x",
        "   "},
       {"?OX",  -- side pattern - cut
        "X.O",
        "   "},
       }

pat_gridcular_seq = {  -- Sequence of coordinate offsets of progressively wider diameters in gridcular metric
        {{0,0},
         {0,1}, {0,-1}, {1,0}, {-1,0},
         {1,1}, {-1,1}, {1,-1}, {-1,-1}, },  -- d=1,2 is not considered separately
        {{0,2}, {0,-2}, {2,0}, {-2,0}, },
        {{1,2}, {-1,2}, {1,-2}, {-1,-2}, {2,1}, {-2,1}, {2,-1}, {-2,-1}, },
        {{0,3}, {0,-3}, {2,2}, {-2,2}, {2,-2}, {-2,-2}, {3,0}, {-3,0}, },
        {{1,3}, {-1,3}, {1,-3}, {-1,-3}, {3,1}, {-3,1}, {3,-1}, {-3,-1}, },
        {{0,4}, {0,-4}, {2,3}, {-2,3}, {2,-3}, {-2,-3}, {3,2}, {-3,2}, {3,-2}, {-3,-2}, {4,0}, {-4,0}, },
        {{1,4}, {-1,4}, {1,-4}, {-1,-4}, {3,3}, {-3,3}, {3,-3}, {-3,-3}, {4,1}, {-4,1}, {4,-1}, {-4,-1}, },
        {{0,5}, {0,-5}, {2,4}, {-2,4}, {2,-4}, {-2,-4}, {4,2}, {-4,2}, {4,-2}, {-4,-2}, {5,0}, {-5,0}, },
        {{1,5}, {-1,5}, {1,-5}, {-1,-5}, {3,4}, {-3,4}, {3,-4}, {-3,-4}, {4,3}, {-4,3}, {4,-3}, {-4,-3}, {5,1}, {-5,1}, {5,-1}, {-5,-1}, },
        {{0,6}, {0,-6}, {2,5}, {-2,5}, {2,-5}, {-2,-5}, {4,4}, {-4,4}, {4,-4}, {-4,-4}, {5,2}, {-5,2}, {5,-2}, {-5,-2}, {6,0}, {-6,0}, },
        {{1,6}, {-1,6}, {1,-6}, {-1,-6}, {3,5}, {-3,5}, {3,-5}, {-3,-5}, {5,3}, {-5,3}, {5,-3}, {-5,-3}, {6,1}, {-6,1}, {6,-1}, {-6,-1}, },
        {{0,7}, {0,-7}, {2,6}, {-2,6}, {2,-6}, {-2,-6}, {4,5}, {-4,5}, {4,-5}, {-4,-5}, {5,4}, {-5,4}, {5,-4}, {-5,-4}, {6,2}, {-6,2}, {6,-2}, {-6,-2}, {7,0}, {-7,0}, },
    }
spat_patterndict_file = 'patterns.spat'
large_patterns_file = 'patterns.prob'

-- until line -> 134 <- in michi
