local M = {}

local RUN_BLOCK_START = "#!"
local RUN_BLOCK_END = "#/>"
local OUT_BLOCK_START = "--------[out]---"
local OUT_BLOCK_END = "--------[end]---"

function get_run_block()
    local buf = vim.api.nvim_get_current_buf()
    local buf_row_count = vim.api.nvim_buf_line_count(buf)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local cursor_row = cursor[1] - 1

    -- search upwards for start of block
    local row = cursor_row
    local block_start = row
    repeat
        local line = vim.api.nvim_buf_get_lines(buf, row, row+1, true --[[strict]])[1]
        if line:sub(0, 2) == RUN_BLOCK_START then
            block_start = row
            break
        end
        row = row - 1
    until line == RUN_BLOCK_END or row < 0
    
    -- search downwards for end of block
    row = cursor_row
    local block_end = row
    repeat
        local line = vim.api.nvim_buf_get_lines(buf, row, row+1, true --[[strict]])[1]
        if line == RUN_BLOCK_END then
            block_end = row
            break
        end
        row = row + 1
    until line:sub(0, 2) == RUN_BLOCK_START or row >= buf_row_count

    return block_start, block_end
end

function get_out_block(block_start, block_end)
    local buf = vim.api.nvim_get_current_buf()
    local buf_row_count = vim.api.nvim_buf_line_count(buf)

    local start = block_end + 1
    if start >= buf_row_count then
        return nil, nil
    end

    local first_line = vim.api.nvim_buf_get_lines(buf, start, start+1, true --[[strict]])[1]
    if first_line ~= OUT_BLOCK_START then
        return nil, nil
    end

    for finish = start+1, buf_row_count do
        local line = vim.api.nvim_buf_get_lines(buf, finish, finish+1, true --[[strict]])[1]
        if line == OUT_BLOCK_END then
            return start, finish
        end
    end
    return start, nil
end

function run_block(block_start, block_end)
    local buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, block_start, block_end+1, true --[[strict]])

    local tmpname = os.tmpname()
    local f = io.open(tmpname, "w")
    for i = 1, #lines do
        f:write(lines[i].."\n")
    end
    f:close()
    os.execute("chmod +x "..tmpname)
    local handle = io.popen(tmpname.." 2>&1")
    return function()
        local line = handle:read("*l")
        if line == nil then
            handle:close()
        end
        return line
    end
end

function str(val)
    if val == nil then
        return "nil"
    end
    return val
end

function M.run()
    local buf = vim.api.nvim_get_current_buf()
    run_block_start, run_block_end = get_run_block()
    out_block_start, out_block_end = get_out_block(run_block_start, run_block_end)

    -- clear out block
    if out_block_start ~= nil and out_block_end ~= nil then
        vim.api.nvim_buf_set_lines(
            buf, out_block_start, out_block_end+1, true --[[strict]], {}
        )
    end

    local out_line = run_block_end + 1
    vim.api.nvim_buf_set_lines(
         buf, out_line, out_line, true --[[strict]], {OUT_BLOCK_START}
    )
    out_line = out_line + 1
    for line in run_block(run_block_start, run_block_end) do
        vim.api.nvim_buf_set_lines(
             buf, out_line, out_line, true --[[strict]], {line}
        )
        vim.api.nvim_command('redraw')
        out_line = out_line + 1
    end
    vim.api.nvim_buf_set_lines(
         buf, out_line, out_line, true --[[strict]], {OUT_BLOCK_END}
    )
    -- print("run block: ["..str(run_block_start)..", "..str(run_block_end).."]")
    -- print("out block: ["..str(out_block_start)..", "..str(out_block_end).."]")
end
return M
