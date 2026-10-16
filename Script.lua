--[[

position_table example:
Piece.Name :string
Position :table
Taken :boolean

]]

local game_modules = {}
local current_board, current_turn, current_positions, my_color, stockfish_pos, board_model = nil, nil, nil, nil, nil, game.Workspace:FindFirstChild("Board")
local replicated_storage, players = cloneref(game:GetService("ReplicatedStorage")), cloneref(game:GetService("Players"))

game_modules.board, game_modules.stockfish --[[😈😈]] = require(replicated_storage.Modules.Board), require(replicated_storage.Modules.SunfishHandler.Sunfish)

local board_init, next_round, board_spawn = game_modules.board._init, game_modules.board.nextRound, game_modules.board.spawn

for _, v in getgc(true) do
    if type(v) == "table" and rawget(v, "activeTeam") and rawget(v, "players") and rawget(v, "contents") and rawget(v, "tiles") and rawget(v, "boardStates") then
        current_board = v -- for ranked
        if rawget(v, "players")[true] == players.LocalPlayer then
            my_color = "white"
        elseif rawget(v, "players")[false] == players.LocalPlayer then
            my_color = "black"
        else
            my_color = "spectator"
        end
        break
    end
end

local create_higlight = function(from, to)
    if not board_model then return end
    local from_name = from[1] .. "," .. from[2]
    local from_tile = board_model:FindFirstChild(from_name)
    if from_tile then
        local hl = Instance.new("Highlight")
        hl.Adornee = from_tile
        hl.FillColor = Color3.fromRGB(255, 255, 255)
        hl.OutlineColor = Color3.fromRGB(255, 255, 255)
        hl.FillTransparency = 0.5
        hl.Parent = from_tile
    end
    local to_name = to[1] .. "," .. to[2]
    local to_tile = board_model:FindFirstChild(to_name)
    if to_tile then
        local hl = Instance.new("Highlight")
        hl.Adornee = to_tile
        hl.FillColor = Color3.fromRGB(255, 255, 255)
        hl.OutlineColor = Color3.fromRGB(255, 255, 255)
        hl.FillTransparency = 0.5
        hl.Parent = to_tile
    end
end
local destroy_higlight = function()
    if not board_model then return end
    for _, v in board_model:GetChildren() do
        for _, h in v:GetChildren() do
            if h:IsA("Highlight") then
                h:Destroy()
            end
        end
    end
end

game_modules.board._init = function(...)
	local args = {...}
	current_board = args[1]
	if args[2] == players.LocalPlayer then
		my_color = "white"
	elseif args[3] == players.LocalPlayer then
		my_color = "black"
	else
		my_color = "spectator"
	end
	return board_init(...)
end
game_modules.board.spawn = function(...)
    board_model = nil
    board_spawn(...)
    board_model = game.Workspace:FindFirstChild("Board")
end

local piece_to_character = {
	Pawn = {
		[true] = "P",
		[false] = "p"
	},
	Knight = {
		[true] = "N",
		[false] = "n"
	},
	Bishop = {
		[true] = "B",
		[false] = "b"
	},
	Rook = {
		[true] = "R",
		[false] = "r"
	},
	Queen = {
		[true] = "Q",
		[false] = "q"
	},
	King = {
		[true] = "K",
		[false] = "k"
	}
}

local board_string = function()
	local rows = {}
	for y = 8, 1, -1 do
		local row = " "
		for x = 8, 1, -1 do
			local piece = current_board.contents[1][x][y]
			if piece then
				local character = piece_to_character[piece.Name]
				row = row .. (character and character[piece.team] or "?")
			else
				row = row .. "."
			end
		end
		table.insert(rows, row)
	end
	return "         \n         \n" .. table.concat(rows, "\n") .. "\n         \n          "
end

local castling = function(active)
	local rank = active and 1 or 8
	local pieces = active and current_board.whitePieces or current_board.blackPieces
	local king_alive, rook_1, rook_2 = false, false, false
	for _, piece in pairs(pieces) do
		if piece.position then
			if piece.Name == "King" and piece.position[1] == 4 and piece.position[2] == rank then
				king_alive = true
			elseif piece.Name == "Rook" then
				if piece.position[1] == 8 and piece.position[2] == rank then
					rook_1 = true
				elseif piece.position[1] == 1 and piece.position[2] == rank then
					rook_2 = true
				end
			end
		end
	end
	return {
		king_alive and rook_1,
		king_alive and rook_2
	}
end

local get_move = function()
	if not stockfish_pos then
		return nil
	end
	game_modules.stockfish.setFrameKeepingFunction(function(n)
		if n % 1000 == 0 then
			task.wait()
		end
	end)
	local stockfish_results = game_modules.stockfish.search(stockfish_pos, 50000, 4, {
		nodes = 50000,
		depth = 4,
		lategameBonusDepth = 2,
		tradeBonusMult = 0.2,
		aggressionBonus = 30,
		defenseBonus = 10,
		strength = 0,
		targetDepths = {},
		overlookSettings = nil,
		evaluationSettings = nil,
		searchTelemetry = false
	})
	if not stockfish_results or #stockfish_results == 0 then
		return nil
	end
	local best_move, score, rank = game_modules.stockfish.chooseMove(stockfish_results, {
		relativeBadMoveCutoff = -100,
		worseMoveChance = 0
	})
	if not best_move then
		return nil
	end
	local last_pos = game_modules.stockfish.getPosition(best_move[1])
	local next_pos = game_modules.stockfish.getPosition(best_move[2])
	local piece = current_board:getPiece(last_pos)
	return {
		from = last_pos,
		to = next_pos,
		piece = piece,
		score = score,
		is_promotion = best_move[3] == "promotion",
		promotion_piece = best_move[4],
		stockfish_move = best_move
	}
end

game_modules.board.nextRound = function(...)
    if current_board then
        current_positions = game_modules.board.getBoardState(current_board)
        local board_string = board_string()
        local player = current_board.activeTeam
        local wc = castling(true)
        local bc = castling(false)
        if player ~= nil then
            stockfish_pos = game_modules.stockfish.createPosition(board_string, player, 0, wc, bc, 0, 0)
            local move = get_move()
            if move then
                destroy_higlight()
                create_higlight(move.from, move.to)
            end
        end
    end
    return next_round(...)
end
