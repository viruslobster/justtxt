local M = {}

local EXE_BLOCK_START = "^#![^!]?"
local EXE_BLOCK_END = "^#/>"
local OUT_BLOCK_START = "--------[out]---"
local OUT_BLOCK_END = "--------[end]---"

function get_line(self, i)
    return vim.api.nvim_buf_get_lines(self.id, i, i+1, true)[1]
end

function get_lines(self, i, j)
    return vim.api.nvim_buf_get_lines(self.id, i, j, true)
end

function set_lines(self, i, j, lines)
    vim.api.nvim_buf_set_lines(self.id, i, j, true, lines)
end

function append_line(self, i, line)
    vim.api.nvim_buf_set_lines(self.id, i, i, true, {line})
end 

function buffer_data()
    local id = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    return {
        id = id,
        len = vim.api.nvim_buf_line_count(id),
        cursor_y = cursor[1] - 1,
        cursor_x = cursor[2],
        get_line = get_line,
        get_lines = get_lines,
        set_lines = set_lines,
        append_line = append_line,
    }
end

function find_run_block(buf)
    -- search upwards for start of block
    local block_start = buf.cursor_y
    for i = buf.cursor_y, 0, -1 do
        local line = buf:get_line(i)
        if line:match(EXE_BLOCK_START) then
            block_start = i
            break
        end
        if line:match(EXE_BLOCK_END) and i ~= buf.cursor_y then
            break -- we've gone too far
        end
    end
    
    -- search downwards for end of block
    local block_end = buf.cursor_y
    for i = buf.cursor_y, buf.len - 1 do
        local line = buf:get_line(i)
        if line:match(EXE_BLOCK_END) then
            block_end = i
            break
        end
        if line:match(EXE_BLOCK_START) and i ~= buf.cursor_y then
            break -- we've gone too far
        end
    end

    return block_start, block_end
end

function get_out_block(buf, block_start, block_end)
    local start = block_end + 1
    if start >= buf.len then
        return nil, nil
    end

    local first_line = buf:get_line(start)
    if first_line ~= OUT_BLOCK_START then
        return nil, nil
    end

    for finish = start+1, buf.len do
        local line = buf:get_line(finish)
        if line == OUT_BLOCK_END then
            return start, finish
        end
    end
    return start, nil
end

function create_cmd(buf, block_start, block_end)
    local lines = buf:get_lines(block_start, block_end+1)

    -- multiline blocks can specify a !! command on the second line
    -- e.g. # !! < input | grep result | wc -l
    local bangbang = "!!"
    if block_start ~= block_end then
        local line = buf:get_line(block_start+1)
        if line:match("^#.*!!") then bangbang = line:sub(2) end
    end

    local script = os.tmpname()
    local f = io.open(script, "w")
    for i = 1, #lines do
        f:write(lines[i].."\n")
    end
    f:close()
    os.execute("chmod +x "..script)
    return bangbang:gsub("!!", script).."\n"
end

function str(val)
    if val == nil then
        return "nil"
    end
    return val
end

function M.kill()
    -- actual implementation is set each time run is called
end

function counter(i)
    return function()
        local buf = i
        i = i + 1
        return buf
    end
end

function M.run()
    local buf = buffer_data();
    exe_start, exe_end = find_run_block(buf)
    -- print("run block: ["..str(exe_start)..", "..str(exe_end).."]")
    out_start, out_end = get_out_block(buf, exe_start, exe_end)
    -- print("out block: ["..str(out_start)..", "..str(out_end).."]")

    -- clear out block
    if out_start ~= nil and out_end ~= nil then
        buf:set_lines(out_start, out_end+1, {})
    end

    local cmd = create_cmd(buf, exe_start, exe_end)

    local stdin = vim.loop.new_pipe(false)
    local stdout = vim.loop.new_pipe(false)
    local stderr = vim.loop.new_pipe(false)

    local handle, pid

    handle, pid = vim.loop.spawn("bash", {
        stdio = {stdin, stdout, stderr},
        detached = true,
    }, function(code, signal) -- on exit
        handle:close()
        M.kill = function() end
    end)

    M.kill = function(signum)
        os.execute("kill -2 -"..pid)
        handle:close()
        M.kill = function() end
    end

    local next_line = counter(exe_end + 1)
    buf:append_line(next_line(), OUT_BLOCK_START)

    local on_update = function(data)
        vim.schedule(function()
            for line in data:gmatch("([^\n]*)\n") do
                buf:append_line(next_line(), line)
            end
            vim.api.nvim_command('redraw')
        end)
    end

    stdout:read_start(function(err, data)
        assert(not err, err)
        if data then
            on_update(data)
        else
            vim.schedule(function()
                buf:append_line(next_line(), OUT_BLOCK_END)
            end)
            stdout:close()
        end
    end)

    stderr:read_start(function(err, data)
        assert(not err, err)
        if data then
            on_update(data)
        else
            stderr:close()
        end
    end)

    stdin:write(cmd)
    stdin:shutdown()

end

return M
