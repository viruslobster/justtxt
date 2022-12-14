local M = {}

local EXE_CELL_START = "^#![^!]*$"
local EXE_CELL_END = "^#%$"
local OUT_CELL_END = "#~"

CellIndex = {}
CellIndex.__index = CellIndex

function CellIndex:new()
    o = {}
    setmetatable(o, self)
    
    o.cell_by_pid = {}
    return o
end

function CellIndex:get(pid)
    return self.cell_by_pid[pid]
end

function CellIndex:set(pid, cell)
    self.cell_by_pid[pid] = cell
end

function CellIndex:del(pid)
    local c = self.cell_by_pid[pid]
    self.cell_by_pid[pid] = nil
    return c
end

function CellIndex:selected_pid(buf, line)
    for pid, cell in pairs(self.cell_by_pid) do
        local start_line = buf:get_extmark(cell.start_mark)
        local end_line = buf:get_extmark(cell.end_mark)

        if line >= start_line and line <= end_line then
            return pid, cell
        end
    end
    return nil, nil
end

local running_cells = CellIndex:new()

Buffer = {
    NVIM_JUSTTXT_NS = vim.api.nvim_create_namespace("justtxt")
}
Buffer.__index = Buffer

function Buffer:new()
    local o = {}
    setmetatable(o, Buffer)

    local cursor = vim.api.nvim_win_get_cursor(0)
    self.id = vim.api.nvim_get_current_buf()
    self.len = vim.api.nvim_buf_line_count(self.id)
    self.cursor_y = cursor[1] - 1
    self.cursor_x = cursor[2]
    return o
end

function Buffer:get_line(i)
    return vim.api.nvim_buf_get_lines(self.id, i, i+1, true)[1]
end

function Buffer:get_lines(i, j)
    return vim.api.nvim_buf_get_lines(self.id, i, j, true)
end

function Buffer:set_lines(i, j, lines)
    vim.api.nvim_buf_set_lines(self.id, i, j, true, lines)
end

function Buffer:append_line(i, line)
    vim.api.nvim_buf_set_lines(self.id, i, i, true, {line})
end 

function Buffer:set_extmark(line)
    return vim.api.nvim_buf_set_extmark(
        self.id, self.NVIM_JUSTTXT_NS, line, 0, {}
    )
end

function Buffer:get_extmark(id)
    local line = vim.api.nvim_buf_get_extmark_by_id(
        self.id, self.NVIM_JUSTTXT_NS, id, {}
    )[1]
    return line
end

function Buffer:del_extmark(id)
    vim.api.nvim_buf_del_extmark(self.id, self.NVIM_JUSTTXT_NS, id)
end

function Buffer:redraw()
    vim.api.nvim_command('redraw')
end

function cell(start_mark, end_mark)
    return {
        start_mark = start_mark,
        end_mark = end_mark, 
    }
end

function find_run_cell(buf)
    local line = buf:get_line(buf.cursor_y)
    if line:match("^!") then
        return buf.cursor_y, buf.cursor_y
    end

    -- search upwards for start of cell
    local cell_start = nil
    for i = buf.cursor_y, 0, -1 do
        local line = buf:get_line(i)
        if line:match(EXE_CELL_START) then
            cell_start = i
            break
        end
        if line:match(EXE_CELL_END) and i ~= buf.cursor_y then
            break -- we've gone too far
        end
    end
    
    -- search downwards for end of cell
    local cell_end = nil
    for i = buf.cursor_y, buf.len - 1 do
        local line = buf:get_line(i)
        if line:match(EXE_CELL_END) then
            cell_end = i
            break
        end
        if line:match(EXE_CELL_START) and i ~= buf.cursor_y then
            break -- we've gone too far
        end
    end

    return cell_start, cell_end
end

function get_out_cell(buf, exe_cell_end)
    local start = exe_cell_end + 1
    if start >= buf.len then
        return nil, nil
    end

    for finish = start, buf.len-1 do
        local line = buf:get_line(finish)
        if line:match(OUT_CELL_END) then
            return start, finish
        end

        if line:match(EXE_CELL_START) then
            break -- we've gone too far
        end

        if  line:match("^!") then
            break -- we've gone too far
        end
    end
    return start, nil
end

function create_cmd(buf, cell_start, cell_end)
    local lines = buf:get_lines(cell_start, cell_end+1)

    if cell_start == cell_end then
        lines[1] = lines[1]:gsub("^%s*!?%s*", "")
    end

    -- multiline cells can specify a !! command on the second line
    -- e.g. # !! < input | grep result | wc -l
    local bangbang = "!!"
    if cell_start ~= cell_end then
        local line = buf:get_line(cell_start+1)
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
    local buf = Buffer:new()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = cursor[1] - 1
    local pid, cell = running_cells:selected_pid(buf, line)
    if pid == nil then
        print("No cell selected")
        return
    end

    os.execute("kill -2 -"..pid)
    -- local i = buf:get_extmark(cell.end_mark)
    -- buf:set_lines(i, i+1, { OUT_CELL_END.." Sent SIGINT" })
    -- TODO process might not actually be done
end

function fmt_run_cell(buf, exe_start, exe_end)
    if exe_start ~= exe_end then
        return -- only fmt rules for one line cells right now
    end
    local line = buf:get_line(exe_start)
    local suffix = line:gsub("^%s*!?%s*", "")
    buf:set_lines(exe_start, exe_start+1, {"! "..suffix})
end

function M.clear()
    local buf = buffer_data();
    exe_start, exe_end = find_run_cell(buf)
    if exe_start and exe_end then
    end
end

function M.run()
    local buf = Buffer:new()
    exe_start, exe_end = find_run_cell(buf)
    if exe_start == nil and exe_end == nil then
        -- no run cell found, assume we want to run the current line
        exe_start = buf.cursor_y
        exe_end = buf.cursor_y
    end

    -- print("run cell: ["..str(exe_start)..", "..str(exe_end).."]")
    out_start, out_end = get_out_cell(buf, exe_end)
    -- print("out cell: ["..str(out_start)..", "..str(out_end).."]")
     
    fmt_run_cell(buf, exe_start, exe_end)

    -- clear out cell
    if out_start ~= nil and out_end ~= nil then
        buf:set_lines(out_start, out_end+1, {})
    end

    local cmd = create_cmd(buf, exe_start, exe_end)

    local start_mark = buf:set_extmark(exe_start)

    buf:append_line(exe_end+1, OUT_CELL_END.." RUNNING")
    local end_mark = buf:set_extmark(exe_end+1)

    local stdin = vim.loop.new_pipe(false)
    local stdout = vim.loop.new_pipe(false)
    local stderr = vim.loop.new_pipe(false)

    local handle, pid

    handle, pid = vim.loop.spawn("bash", {
        stdio = {stdin, stdout, stderr},
        detached = true, -- make bash the process group leader
    }, function(code, signal) -- on exit
        handle:close()

        vim.schedule(function()
            local i = buf:get_extmark(end_mark)
            buf:set_lines(i, i+1, { OUT_CELL_END })

            local c = running_cells:del(pid)
            buf:del_extmark(c.start_mark)
            buf:del_extmark(c.end_mark)
        end)
    end)

    running_cells:set(pid, cell(start_mark, end_mark))

    local on_update = function(data)
        vim.schedule(function()
            local i = buf:get_extmark(end_mark)
            for line in data:gmatch("([^\n]*)\n") do
                buf:append_line(i, line)
                i = i + 1
            end
            buf:redraw()
        end)
    end

    stdout:read_start(function(err, data)
        assert(not err, err)
        if data then
            on_update(data)
        else
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
