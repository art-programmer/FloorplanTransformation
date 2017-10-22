require 'nn'
require 'cunn'
require 'cudnn'
require 'fbnn'
require 'fbcunn'
local cjson = require 'cjson'
-- Convert a file to json.

local pl = require'pl.import_into'()

local function merge(t_dst, t_src)
    for i, v in ipairs(t_src) do
        table.insert(t_dst, v)
    end
    return t_dst
end

local function extract_array(t)
    local all_array = {}
    if type(t) == 'table' then
        for i, v in ipairs(t) do
            merge(all_array, extract_array(v))
        end
    elseif torch.typename(t) and torch.typename(t):match('Tensor') then
        t:apply(function (x) table.insert(all_array, x) end)
    else
        error("Input is not a table or a tensor!")
    end
    return all_array
end

local function recursive_save(t, name_prefix)
    local all_array = {}
    local all_save = {}

    print(name_prefix)

    if type(t) == 'table' then
        for k, v in pairs(t) do
            if type(k) == 'string' then
                save_content = recursive_save(v, name_prefix .. "_" .. k)
                for kk, vv in pairs(save_content) do
                    all_save[kk] = vv
                end
            elseif type(k) == 'number' then
                -- Save v with the existing prefix.
                -- For tensor, save every element. 
                merge(all_array, extract_array(v))
            end 
        end
    else
        all_array = extract_array(t)
    end

    if #all_array > 0 then all_save[name_prefix] = all_array end
    return all_save
end

local opt = pl.lapp[[
   -i,--input         (default "")  Input model
   -o,--outputprefix  (default "")  Output model 
]]

local save_content = recursive_save(torch.load(opt.input), opt.outputprefix)
for name, content in pairs(save_content) do
    local f = assert(io.open(name, "w"))
    f:write(cjson.encode(content))
    f:close()
end
