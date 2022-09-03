#!/usr/bin/env lua
local justtext = require("justtxt")

local test = {}
function test.thing1()
    assert(false, "needs to be true")
end

function test.thing2()
end

function run()
    local sorted_tests = {}
    for name, test in pairs(test) do
        table.insert(sorted_tests, {name = name, test = test})
    end
    table.sort(sorted_tests, function (a, b) return a.name < b.name end)

    for _, t in ipairs(sorted_tests) do
        local ok, err = pcall(t.test)
        if ok then
            print(t.name..": success!")
        else
            print(t.name..": failed =(")
            print("    "..err)
        end
    end
end
run()
