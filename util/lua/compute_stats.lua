-- Compute network status.
local transform = require 'torchnet.transform'

local stats = {}

local function get_layer(model, layer_names)
    local res = {}

    -- local inv_table = {}
    -- for _, l in pairs(layer_names) do inv_table[l] = true end

    for i = 1, #model.modules do
        local m = model.modules[i]

        if layer_names[torch.typename(m)] then 
            table.insert(res, m) 
        elseif m.modules then
            local prev = get_layer(m, layer_names)
            for _, mm in ipairs(prev) do
                table.insert(res, mm)
            end
        end
    end
    return res
end

function stats.get_relus(model)
    local layer_names = { ["nn.ReLU"] = true, ["cudnn.ReLU"] = true }
    return get_layer(model, layer_names)
end

function stats.get_fcs(model)
    local fc_layers = {}
    for i = 1, #model.modules do
        local m = model.modules[i]
        if torch.typename(m) == 'nn.Linear' then
            local prev_layer = (i == 1 and 'input' or model.modules[i-1])
            table.insert(fc_layers, {prev_layer, model.modules[i] })
        end
    end
    return fc_layers
end

local function permute_stats(stats) 
    for j = 1, #stats do
        local perm = {}
        for rr = 3, stats[j]:nDimension() do table.insert(perm, rr) end
        table.insert(perm, 1); table.insert(perm, 2)

        stats[j] = stats[j]:permute(unpack(perm))
    end
end

function stats.create_cell(dims)
    local counter = {}
    for i = 1, #dims do
        counter[i] = 1
    end

    local done = false
    local t = {}
    while not done do
        -- Based on current 
        local currt = t
        for i = 1, #dims do
            if not currt[counter[i]] then currt[counter[i]] = {} end
            currt = currt[counter[i]]
        end

        -- Advance
        done = true
        for i = #dims, 1, -1 do
            counter[i] = counter[i] + 1
            if counter[i] <= dims[i] then 
                done = false
                break 
            end
            counter[i] = 1
        end
    end

    return t
end

local function evaluate_through(model, all_data, all_labels, nBatch, func)
    model:evaluate()
    local nTrain = all_data:size(1)
    nBatch = nBatch or 128
    local accuracy = 0.0

    -- Statistics
    for i = 1, nTrain, nBatch do
        local data = all_data[{{i, i + nBatch - 1}, {}}]
        local res = model:forward(data:cuda())
        local gt_labels = all_labels:sub(i, i + nBatch - 1):float()

        func(data, gt_labels, res)

        best_score, best_idx = torch.max(res, 2)
        accuracy = accuracy + best_idx:float():eq(gt_labels):sum()
    end
    return accuracy / nTrain
end

function stats.torchnet_evaluator(model, dataset, collector, maxload)
    local n = 0
    local perm = transform.randperm(dataset:size())
    local accuracy = 0.0

    local crit = collector.needbackprop and nn.ClassNLLCriterion():cuda()
    if collector.needbackprop then model:training() else model:evaluate() end

    if collector.starter then collector.starter(model) end

    for sample in dataset:iterator{perm = perm} do
        local input_cuda = sample.input:cuda()
        local res = model:forward(input_cuda)

        if collector.needbackprop then
            -- Also backprop with ground truth data
            local target_cuda = torch.squeeze(sample.target):cuda()

            crit:forward(res, target_cuda)
            model:zeroGradParameters()
            crit:backward(res, target_cuda)
            model:backward(input_cuda, crit.gradInput)
        end

        if collector.collector then collector.collector(input_cuda, sample.target) end

        best_score, best_idx = torch.max(res, 2)
        accuracy = accuracy + best_idx:double():eq(sample.target):sum()
        n = n + input_cuda:size(1)
        if n >= maxload then break end
    end

    if collector.finalizer then collector.finalizer(model) end

    return accuracy / n, collector.returner()
end

function stats.node_stats_collector(nClass)
    -- Check how many ReLU layers are there.
    -- Statistics
    -- layer, node id -> K by 2 tensor.
    local node_stats = {}
    local relu_layers = {}

    local collector = function (batch_input, batch_target)
        -- Get layer statistics
        local n_batch = batch_input:size(1)
        for j = 1, #relu_layers do
            local output = relu_layers[j].output:clone()
            local dim = torch.totable(output[1]:size())
            if not node_stats[j] then
                node_stats[j] = torch.zeros(nClass, 2, unpack(dim))            
            end
                
            local high = output:ge(1e-4):double()
            local low = output:lt(1e-4):double()
                    
            for k = 1, n_batch do
                local t = batch_target[k]
                if type(t) ~= 'number' then t = torch.squeeze(t) end
                local s = node_stats[j][t]
                assert(s, string.format("stats.node_stats_collector out of bound. j = %d, batch_target[%d] = %d", j, k, t))
                s[1]:add(low[k])
                s[2]:add(high[k])
            end       
        end
    end

    -- local accuracy = evaluate_through(model, all_data, all_labels, nBatch, collector)
    -- return node_stats, relu_layers, accuracy
    return { 
        returner = function () return node_stats, relu_layers end, 
        starter = function (model) relu_layers = stats.get_relus(model) end, 
        collector = collector, 
        finalizer = function () permute_stats(node_stats) end 
    }
end

function stats.node_grad_corr_collector(nClass)
    local node_stats = {}
    local relu_layers = {}

    local collector = function (batch_input, batch_target)
        -- Get layer statistics
        local n_batch = batch_input:size(1)
        for j = 1, #relu_layers do
            local gradInput = relu_layers[j].gradInput:clone()

            local dim = torch.totable(gradInput[1]:size())
            if not node_stats[j] then
                node_stats[j] = torch.zeros(nClass, 2, unpack(dim))            
            end
                
            local pos = gradInput:gt(1e-4):double()
            local neg = gradInput:lt(-1e-4):double()
                    
            for k = 1, n_batch do
                local t = batch_target[k]
                if type(t) ~= 'number' then t = torch.squeeze(t) end
                local s = node_stats[j][t]
                assert(s, string.format("stats.node_grad_corr_collector out of bound. j = %d, batch_target[%d] = %d", j, k, t))
                s[1]:add(neg[k])
                s[2]:add(pos[k])
            end
        end
    end

    -- local accuracy = evaluate_through(model, all_data, all_labels, nBatch, collector)
    -- return node_stats, relu_layers, accuracy
    return { 
        returner = function () return node_stats, relu_layers end, 
        starter = function (model) relu_layers = stats.get_relus(model) end, 
        collector = collector, 
        needbackprop = true,
        finalizer = function () permute_stats(node_stats) end 
    }
end

--[[
local s = node_stats[j][l][t]
if bConv then
    local gv = gradInput[k][l]:view(-1)
    for kk = 1, gv:size(1) do
        if gv[kk] < -1e-4 then
            table.insert(s[1], img_counter)
        elseif gv[kk] > 1e-4 then
            table.insert(s[2], img_counter)
        end
    end
else
    local gv = gradInput[k][l]
    if gv < -1e-4 then
        table.insert(s[1], img_counter)
    elseif gv > 1e-4 then
        table.insert(s[2], img_counter)
    end
end
]]--

function stats.node_resp_image_collector(nImage, collection_type)
    local node_stats = {}
    local relu_layers = {}
    local batch_inputs = {}
    local batch_targets = {}

    local collector = function (batch_input, batch_target)
        -- Get layer statistics
        local n_batch = batch_input:size(1)
        local baseaddr = #batch_inputs * batch_input:size(1)

        for j = 1, #relu_layers do
            local output = relu_layers[j].output
            local outputAgg
            if output[1]:nDimension() == 3 then
                if collection_type == 'sum' then
                    outputAgg = output:sum(3):sum(4)
                elseif collection_type == 'max' then
                    local agg1, _ = output:max(3)
                    outputAgg, _ = agg1:max(4)
                else
                    error(string.format("collection_type = %s is not defined.", collection_type))
                end
            else
                outputAgg = output:clone()
            end

            -- Check if the 
            local nChannel = output[1]:size(1)
            if not node_stats[j] then
                node_stats[j] = torch.FloatTensor(nImage, nChannel):zero()
            end

            assert(baseaddr + 1 <= nImage, string.format("baseaddr + 1 = %d is out of bound (%d)", baseaddr + 1, nImage))
            assert(baseaddr + n_batch <= nImage, string.format("baseaddr + n_batch = %d is out of bound (%d)", baseaddr + n_batch, nImage))

            node_stats[j]:sub(baseaddr + 1, baseaddr + n_batch):copy(outputAgg)
        end
        table.insert(batch_inputs, batch_input:float())
        table.insert(batch_targets, batch_target:float())
    end

    -- local accuracy = evaluate_through(model, all_data, all_labels, nBatch, collector)
    -- return node_stats, relu_layers, accuracy
    return { 
        returner = function () return node_stats, relu_layers, batch_inputs, batch_targets end, 
        starter = function (model) relu_layers = stats.get_relus(model) end, 
        collector = collector, 
        finalizer = function () 
            for i = 1, #node_stats do 
                node_stats[i] = node_stats[i]:transpose(1, 2)
            end
        end
    }
end

function stats.node_grad_image_collector(nImage)
    local node_stats = {}
    local relu_layers = {}
    local batch_inputs = {}
    local batch_targets = {}

    local collector = function (batch_input, batch_target)
        -- Get layer statistics
        local n_batch = batch_input:size(1)
        local baseaddr = #batch_inputs * batch_input:size(1)

        for j = 1, #relu_layers do
            local gradInput = relu_layers[j].gradInput
            local gradInputAgg
            if gradInput[1]:nDimension() == 3 then
                gradInputAgg = gradInput:sum(3):sum(4)
            else
                gradInputAgg = gradInput:clone()
            end

            -- Check if the 
            local nChannel = gradInput[1]:size(1)
            if not node_stats[j] then
                node_stats[j] = torch.FloatTensor(nImage, nChannel):zero()
            end

            assert(baseaddr + 1 <= nImage, string.format("baseaddr + 1 = %d is out of bound (%d)", baseaddr + 1, nImage))
            assert(baseaddr + n_batch <= nImage, string.format("baseaddr + n_batch = %d is out of bound (%d)", baseaddr + n_batch, nImage))

            node_stats[j]:sub(baseaddr + 1, baseaddr + n_batch):copy(gradInputAgg)
        end
        table.insert(batch_inputs, batch_input:float())
        table.insert(batch_targets, batch_target:float())
    end

    -- local accuracy = evaluate_through(model, all_data, all_labels, nBatch, collector)
    -- return node_stats, relu_layers, accuracy
    return { 
        returner = function () return node_stats, relu_layers, batch_inputs, batch_targets end, 
        starter = function (model) relu_layers = stats.get_relus(model) end, 
        collector = collector, 
        needbackprop = true,
        finalizer = function () 
            for i = 1, #node_stats do 
                node_stats[i] = node_stats[i]:transpose(1, 2)
            end
        end
    }
end

function stats.weight_stats(model, all_data, all_labels, nBatch, nClass)
    local fc_layers = stats.get_fcs(model)

    -- weight stats
    local weight_stats = {}
    for j = 1, #fc_layers do weight_stats[j] = {} end

    local collector = function (batch_input, batch_target)  
        -- Get weight stats
        local nbatch = batch_input:size(1)
        for j = 1, #fc_layers do
            -- Get input and output, and compute their cross statistics
            local prev_input = fc_layers[j][1] == 'input' and batch_input or fc_layers[j][1].output                
            local curr = fc_layers[j][2]
            
            if not weight_stats[j].stats then
                weight_stats[j].stats = torch.zeros(nClass, 4, curr.weight:size(1), curr.weight:size(2))
            end

            local high_i = prev_input:ge(1e-4):double()
            local low_i = prev_input:lt(1e-4):double()
            local high_o = curr.output:ge(1e-4):double()
            local low_o = curr.output:lt(1e-4):double()
            
            for k = 1, nbatch do
                local s = weight_stats[j].stats[batch_target[k]]
                s[1]:add(torch.ger(low_o[k], low_i[k]))
                s[2]:add(torch.ger(low_o[k], high_i[k]))
                s[3]:add(torch.ger(high_o[k], low_i[k]))
                s[4]:add(torch.ger(high_o[k], high_i[k]))
            end
        end
    end

    local accuracy = evaluate_through(model, all_data, all_labels, nBatch, collector)
    for j = 1, #fc_layers do
        weight_stats[j].stats = weight_stats[j].stats:permute(3, 4, 2, 1)
    end
    return weight_stats, fc_layers, accuracy
end

return stats