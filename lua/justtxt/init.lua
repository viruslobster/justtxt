local M = {}

local EXE_BLOCK_START = "^#![^!]?"
local EXE_BLOCK_END = "^#/>"
local OUT_BLOCK_START = "--------[out]---"
local OUT_BLOCK_END = "--------[end]---"

function buffer_data()
    local id = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    return {
        id = id,
        len = vim.api.nvim_buf_line_count(id),
        cursor_y = cursor[1] - 1,
        cursor_x = cursor[2],
    }
end

function find_run_block(buf)
    -- search upwards for start of block
    local row = buf.cursor_y
    local block_start = row
    for i = row, 0, -1 do
        local line = vim.api.nvim_buf_get_lines(buf.id, i, i+1, true)[1]
        if line:match(EXE_BLOCK_START) then
            block_start = i
            break
        end
        if line:match(EXE_BLOCK_END) then
            break -- we've gone too far
        end
    end
    
    -- search downwards for end of block
    row = buf.cursor_y
    local block_end = row
    for i = row, buf.len - 1 do
        local line = vim.api.nvim_buf_get_lines(buf.id, i, i+1, true)[1]
        if line:match(EXE_BLOCK_END) then
            block_end = i
            break
        end
        if line:match(EXE_BLOCK_START) then
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

    local first_line = vim.api.nvim_buf_get_lines(buf.id, start, start+1, true)[1]
    if first_line ~= OUT_BLOCK_START then
        return nil, nil
    end

    for finish = start+1, buf.len do
        local line = vim.api.nvim_buf_get_lines(buf.id, finish, finish+1, true)[1]
        if line == OUT_BLOCK_END then
            return start, finish
        end
    end
    return start, nil
end

function create_cmd(buf, block_start, block_end)
    local lines = vim.api.nvim_buf_get_lines(buf.id, block_start, block_end+1, true)

    -- multiline blocks can specify a !! command on the second line
    -- e.g. # !! < input | grep result | wc -l
    local bangbang = "!!"
    if block_start ~= block_end then
        local line = vim.api.nvim_buf_get_lines(buf.id, block_start+1, block_start+2, true)[1]
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
    os.execute("echo old impl >> /tmp/out")
end

function M.run()
    local buf = buffer_data();
    exe_start, exe_end = find_run_block(buf)
    out_start, out_end = get_out_block(buf, exe_start, exe_end)

    -- clear out block
    if out_start ~= nil and out_end ~= nil then
        vim.api.nvim_buf_set_lines(
            buf.id, out_start, out_end+1, true, {}
        )
    end

    local cmd = create_cmd(buf, exe_start, exe_end)

    local stdin = vim.loop.new_pipe()
    local stdout = vim.loop.new_pipe()
    local stderr = vim.loop.new_pipe()

    local out_line = exe_end + 1
    local handle, pid = vim.loop.spawn("bash", {
        stdio = {stdin, stdout, stderr}
    }, function(code, signal) -- on exit
        stdout:read_stop()
    end)

    M.kill = function(signum)
        os.execute("echo ran kill >> /tmp/out")
        -- vim.loop.kill(pid, signum)
        handle:kill(signum)
        -- handle:close()
    end

    vim.api.nvim_buf_set_lines(
         buf.id, out_line, out_line, true, {OUT_BLOCK_START}
    )

    stdout:read_start(function(err, data)
        assert(not err, err)
        if data then
            vim.schedule(function()
                for line in data:gmatch("([^\n]*)\n") do
                    out_line = out_line + 1
                    vim.api.nvim_buf_set_lines(
                        buf.id, out_line, out_line, true, {line}
                    )
                end
                vim.api.nvim_command('redraw')
            end)
        else 
            vim.schedule(function()
                out_line = out_line + 1
                vim.api.nvim_buf_set_lines(
                     buf.id, out_line, out_line, true, {OUT_BLOCK_END}
                )
            end)
        end
    end)

    stdin:write(cmd, function()
        os.execute("echo 'write is done' >> /tmp/out")
    end)
    stdin:shutdown()

    -- print("run block: ["..str(exe_start)..", "..str(exe_end).."]")
    -- print("out block: ["..str(out_start)..", "..str(out_end).."]")
end


function M.test()
    local signal = vim.loop.new_signal()
    vim.loop.signal_start_oneshot(signal, 17, function(num)
        local pid = vim.loop.os_getpid()
        os.execute("echo finished >>/tmp/out")
    end)

    vim.loop.read_start(stdout, function(err, data)
      assert(not err, err)
      if data then
        os.execute("printf '"..data.."' >> /tmp/out")
      else
        os.execute("echo done >> /tmp/out")
      end
    end)

    print("stdin")
    print(stdin)
    vim.loop.write(stdin, "echo hello\n")
end
return M
