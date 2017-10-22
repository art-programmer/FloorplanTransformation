require 'torch'
require 'nn'
require 'cunn'
require 'cudnn'
require 'fbnn'
require 'fbcunn'
require 'fbcode.deeplearning.experimental.yuandong.layers.custom_layers'

local pl = require 'pl.import_into'()
local tnt = require 'torchnet'
local bistro = require 'bistro'
local cjson = require 'cjson'

-- Some global variables. 

local conv_layer, relu_layer, maxpool_layer

if cudnn then
    conv_layer = cudnn.SpatialConvolution
    relu_layer = cudnn.ReLU
    maxpool_layer = cudnn.SpatialMaxPooling
else 
    conv_layer = nn.SpatialConvolutionMM
    relu_layer = nn.ReLU
    maxpool_layer = nn.SpatialMaxPooling
end

-- Some local utility that make networks.
-- make_network, it take layer specification + inputdim as input, return the actual layer and output dim.
local function conv_layer_size(inputsize, kw, dw, pw)
    dw = dw or 1
    pw = pw or 0
    return math.floor((inputsize + pw * 2 - kw) / dw) + 1
end

local function spatial_layer_size(layer, inputdim)
    layer.nip = layer.nip or inputdim[2]
    layer.nop = layer.nop or layer.nip

    -- print(pl.pretty.write(inputdim))
    assert(#inputdim == 4, 'Spatial_layer_size: Input dim must be 4 dimensions')
    assert(layer.nip == inputdim[2], string.format('Spatial_layer_size: the number of input channel [%d] is not the same as specified [%d]!', inputdim[2], layer.nip))
    assert(layer.nop, 'Spatial_layer_size: layer.nop is null!')

    layer.pw = layer.pw or 0
    layer.dw = layer.dw or 1

    layer.kh = layer.kh or layer.kw
    layer.ph = layer.ph or layer.pw
    layer.dh = layer.dh or layer.dw

    local outputw = conv_layer_size(inputdim[4], layer.kw, layer.dw, layer.pw)
    local outputh = conv_layer_size(inputdim[3], layer.kh, layer.dh, layer.ph)

    return {inputdim[1], layer.nop, outputh, outputw}
end

local function spec_expand(dim, spec, inputdim)
    local res = {}
    local total = 0
    for i = 1, #spec do
        if type(spec[i]) == 'table' then
            this_res, this_total = spec_expand(dim, spec[i], inputdim)
        else
            this_res = pl.tablex.deepcopy(inputdim)
            this_res[dim] = spec[i]
            this_total = spec[i]
        end
        table.insert(res, this_res)
        total = total + this_total
    end
    return res, total
end

local function make_network(layer, inputdim)
    -- if layer.showinputdim then
        print("++++++++++++++++++++++++++++")
        print("Layer spec = " .. pl.pretty.write(layer, '', false))
        print("Input dim = " .. pl.pretty.write(inputdim, '', false))
        print("----------------------------")
    -- end

    if not layer.type or layer.type == 'seq' then
        local seq = nn.Sequential()

        -- Maka a sequential network
        local curr_inputdim = inputdim
        local ll
        for _, l in ipairs(layer) do
            ll, curr_inputdim = make_network(l, curr_inputdim)
            seq:add(ll)
        end
        return seq, curr_inputdim

    elseif layer.type == 'parallel' then
        local para = nn.ParallelTable()

        local ll
        local outputdim = {}
        for idx, l in ipairs(layer) do
            ll, outputdim[idx] = make_network(l, inputdim[idx])
            para:add(ll)
        end
        return para, outputdim
    elseif layer.type == 'join' then
        assert(type(inputdim) == 'table', 'MakeNetwork::Join: inputdim must be a table!')

        local outputdim
        for idx, dim in ipairs(inputdim) do
            if not outputdim then 
                outputdim = dim
            else
                for dim_idx, d_size in ipairs(dim) do
                    if dim_idx == layer.dim then
                        outputdim[dim_idx] = outputdim[dim_idx] + d_size
                    else
                        assert(outputdim[dim_idx] == d_size, 'Join table, dimension ' .. dim_idx .. ' disagree!')
                    end
                end
            end
        end
        return nn.JoinTable(layer.dim), outputdim

    elseif layer.type == 'conv' then
        layer.nip = layer.nip or inputdim[2]
        layer.dw = layer.dw or 1

        layer.kh = layer.kh or layer.kw
        layer.dh = layer.dh or layer.dw

        layer.pw = layer.pw or math.floor(layer.kw / 2)
        layer.ph = layer.ph or math.floor(layer.kh / 2)

        assert(layer.nip == inputdim[2], string.format('MakeNetwork::Conv: #input channel [%d] must match with specification [%d]!', inputdim[2], layer.nip));        
        assert(layer.kw)
        assert(layer.kh)
        assert(layer.pw)
        assert(layer.ph)
        assert(layer.dw)
        assert(layer.dh)
        assert(layer.nip)
        assert(layer.nop)

        local conv_layer = conv_layer(layer.nip, layer.nop, layer.kw, layer.kh, layer.dw, layer.dh, layer.pw, layer.ph)
        return conv_layer, spatial_layer_size(layer, inputdim)

    elseif layer.type == 'relu' then
        return relu_layer(), inputdim

    elseif layer.type == 'bn' then
        assert(#inputdim == 2, 'Error! Input to BatchNormalization must be 2-dimensional.')
        return nn.BatchNormalization(inputdim[2]), inputdim

    elseif layer.type == 'spatialbn' then
        assert(#inputdim == 4, 'Error! Input to SpatialBatchNormalization must be 4-dimensional.')
        return nn.SpatialBatchNormalization(inputdim[2]), inputdim

    elseif layer.type == 'thres' then
        return nn.Threshold(0, 1e-6), inputdim

    elseif layer.type == 'maxp' then
        assert(layer.kw and layer.dw, "MakeNetwork:MaxP: kw and dw should not be nil")

        layer.kh = layer.kh or layer.kw
        layer.dh = layer.dh or layer.dw

        return maxpool_layer(layer.kw, layer.kh, layer.dw, layer.dh), spatial_layer_size(layer, inputdim)

    elseif layer.type == 'maxp1' then
        assert(layer.kw and layer.dw, "MakeNetwork:MaxP1: kw and dw should not be nil")
        local outputdim = { inputdim[1], conv_layer_size(inputdim[2], layer.kw, layer.dw), inputdim[3] }
        return nn.TemporalMaxPooling(layer.kw, layer.dw), outputdim

    elseif layer.type == 'reshape' then
        if layer.dir == '4-2' then
            layer.wi = layer.wi or inputdim[4]
            layer.nip = layer.nip or inputdim[2]
            layer.nop = layer.nop or inputdim[2]*inputdim[3]*inputdim[4]
        elseif layer.dir == '3-2' then
            -- For temporal 1D network, inputdim[2] is the length and inputdim[3] is the number of channels.
            layer.wi = layer.wi or inputdim[2]
            layer.nip = layer.nip or inputdim[3]
            layer.nop = layer.nop or inputdim[2]*inputdim[3]
        end

        if layer.wi then
            -- Reshape from image to vector.
            if layer.dir == '4-2' then
               layer.hi = layer.hi or inputdim[3]

               assert(#inputdim == 4, 'MakeNetwork::Reshape4-2: Input dim must be 4 dimensions')
               local outputsize = { inputdim[1], layer.nip*layer.wi*layer.hi }
               assert(outputsize[2] == inputdim[2]*inputdim[3]*inputdim[4], 'MakeNetwork::Reshape4-2: Input dim must match with specified dimensions')
               assert(outputsize[2] > 0, 
                 string.format("MakeNetwork::Reshape4-2: outputsize[2] = %d, (nip, wi, hi) = (%d, %d, %d)", 
                      outputsize[2], layer.nip, layer.wi, layer.hi))
               return nn.View(outputsize[2]), outputsize
            elseif layer.dir == '3-2' then
               assert(#inputdim == 3, 'MakeNetwork::Reshape3-2: Input dim must be 3 dimensions')
               local outputsize = { inputdim[1], layer.nip*layer.wi }
               assert(outputsize[2] == inputdim[2]*inputdim[3], 'MakeNetwork::Reshape3-2: Input dim must match with specified dimensions')
               assert(outputsize[2] > 0, 
                 string.format("MakeNetwork::Reshape3-2: outputsize[2] = %d, (nip, wi) = (%d, %d)", 
                      outputsize[2], layer.nip, layer.wi))
               return nn.View(outputsize[2]), outputsize
            end
        elseif layer.wo then
            -- Reshape from vector to image.
            assert(#inputdim == 2, 'MakeNetwork::Reshape2-4: Input dim must be 2 dimensions')
            layer.nip = layer.nip or inputdim[2]
            layer.ho = layer.ho or layer.wo
            layer.nop = layer.nop or inputdim[2] / (layer.wo * layer.ho)

            local outputsize = { inputdim[1], layer.nop, layer.ho, layer.wo }
            assert(outputsize[2]*outputsize[3]*outputsize[4] == inputdim[2], 'MakeNetwork::Reshape2-4: Input dim must match with specified dimensions')
            return nn.View(layer.nop, layer.ho, layer.wo), outputsize
        end
    elseif layer.type == 'fc' then
        assert(#inputdim == 2, 'MakeNetwork::FC: Input dim must be 2 dimensions')
        layer.nip = layer.nip or inputdim[2]
        assert(layer.nip == inputdim[2], string.format('MakeNetwork::FC: the number of input channel [%d] is not the same as specified [%d]!', inputdim[2], layer.nip))
        return nn.Linear(layer.nip, layer.nop), { inputdim[1], layer.nop }

    elseif layer.type == 'conv1' then
        -- inputdim[1] : batchsize
        -- inputdim[2] : input length
        -- inputdim[3] : nip
        assert(layer.kw, 'MakeNetwork:Conv1: kw must be specified')
        assert(#inputdim == 3, 'MakeNetwork:Conv1: Input dim must be 3 dimensions')
        assert(layer.nop, 'MakeNetwork:Conv1: nop must be specified')
        -- Note that for temporal convolutional, 
        layer.nip = layer.nip or inputdim[3]
        layer.dw = layer.dw or 1

        assert(layer.nip == inputdim[3], string.format('MakeNetwork::Conv1: the number of input channels [%d] is not the same as specified [%d]!', inputdim[3], layer.nip))
        local outputdim = {inputdim[1], conv_layer_size(inputdim[2], layer.kw, layer.dw), layer.nop}
        return nn.TemporalConvolution(layer.nip, layer.nop, layer.kw, layer.dw), outputdim

    elseif layer.type == 'usample' then
        assert(#inputdim == 4, 'MakeNetwork::USample: Input dim must be 4 dimensions')
        layer.wi = layer.wi or inputdim[3]
        assert(layer.wi == inputdim[3], string.format('MakeNetwork::USample: Input height [%d] much match with specification [%d].', inputdim[3], layer.wi))
        assert(layer.wi == inputdim[4], string.format('MakeNetwork::USample: Input width [%d] much match with specification [%d].', inputdim[4], layer.wi))
        return nn.SpatialUpSamplingNearest(layer.wo / layer.wi), { inputdim[1], inputdim[2], layer.wo, layer.wo }
    elseif layer.type == 'recursive-split' then
        -- Check if the size are the same.
        -- print("InputDim:")
        -- print(pl.pretty.write(inputdim))

        outputdim, total_use = spec_expand(layer.dim, layer.spec, inputdim)
        assert(total_use == inputdim[layer.dim], string.format("MakeNetwork::RecursiveSplitTable: Total usage specified by layer.spec [%d] is not the same as the inputdim[%d] (which is %d)", total_use, layer.dim, inputdim[layer.dim]))

        return nn.RecursiveSplitTable(layer.dim - 1, #inputdim - 1, layer.spec), outputdim
    elseif layer.type == 'addtable' then
        assert(type(inputdim) == 'table', "MakeNetwork::addtable: Inputdim must be a table.")
        assert(inputdim[1], "MakeNetwork::addtable: Inputdim must not be empty.")

        for i = 2, #inputdim do
            assert(#inputdim[i] == #inputdim[1], string.format("MakeNetwork::addtable: Each entry of input dim must be of the same length, yet #input[%d] = %d while #inputdim[1] = %d", i, #inputdim[i], #inputdim[1]))
            for j = 1, #inputdim[i] do
                assert(inputdim[i][j] == inputdim[1][j], string.format("MakeNetwork::addtable: Each entry of inputdim must be of same size. Now inputdim[%d][%d] = %d while inputdim[1][%d] = %d", i, j, inputdim[i][j], j, inputdim[1][j]))
            end
        end

        return nn.CAddTable(), inputdim[1]
    elseif layer.type == 'dropout' then
        return nn.Dropout(layer.ratio), inputdim
    elseif layer.type == 'logsoftmax' then
        return nn.LogSoftMax(), inputdim
    else
        error("Unknown layer type " .. layer.type);
    end
end

local function merge_tables(tbls)
    if #tbls == 0 then return {} end
    local res = tbls[1]
    for i = 2,#tbls do
        for j = 1, #tbls[i] do
            table.insert(res, tbls[i][j])
        end
    end

    return res
end

local nnutils = {
    make_network = make_network,
    spatial_layer_size = spatial_layer_size,
    merge_tables = merge_tables
}

-- Debugging
local g_nn_dbg = false

function nnutils.dbg_set() 
    g_nn_dbg = true
end

function nnutils.dbg_clear() 
    g_nn_dbg = false
end

function nnutils.dprint(s, ...)
    if g_nn_dbg then
       local p = {...}
       if #p == 0 then print(s) 
       else print(string.format(s, unpack(p))) 
       end
    end
end

-- local debug_mapping = {}
-- function nnutils.dbg_set_mapping(key, value)
--     debug_mapping[key] = value
-- end

-- function nnutils.

-- Get to know whether we are in a bistro run or in a local run, by checking the name of local directory..
function nnutils.in_bistro()
    local cwd = io.popen('pwd'):read("*all")
    local bistro_prefix = '/gfsai-bistro'
    return string.sub(cwd, 1, #bistro_prefix) == bistro_prefix
end

function nnutils.json_stats(t)
   return 'json_stats: ' ..  cjson.encode(t)
end

function nnutils.deepcopy(obj)
  file = torch.MemoryFile() -- creates a file in memory
  file:writeObject(obj) -- writes the object into file
  file:seek(1) -- comes back at the beginning of the file
  return file:readObject() -- gets a clone of object
end

function nnutils.add_if_nonexist(t1, t2)
   for k, v in pairs(t2) do
       if not t1[k] then t1[k] = v end
   end
   return t1
end

function nnutils.get_first_available(t, keys)
  for _, k in ipairs(keys) do
     if t[k] then return k, t[k] end
  end
  return nil, nil
end

---------- Layer-wise operation -----------------

function nnutils.pick_layers(model, name)
    local layers = {}
    for i = 1, #model.modules do
        local m = model.modules[i]
        if torch.typename(m):match(name) then
           table.insert(layers, m)
        end
    end
    return layers
end

function nnutils.operate_layers(model, name, func)
    for i = 1, #model.modules do
        local m = model.modules[i]
        if torch.typename(m):match(name) then 
            func(m)
        end
    end    
end

function nnutils.add_regular_hooks(rack)
    -- Trainer has the following hooks:
    --   start, start-epoch, sample, forward, backward, update, "end-epoch", "end"
    -- Tester has the following hooks:
    --   start, start-epoch, sample, forward, end-epoch, end

    -- hook collectgarbage and synchronize (timing purposes)
    rack:addHook('forward', function() collectgarbage() end)
    if rack.hooks.update then
        rack:addHook('update', function() cutorch.synchronize() end)
    end

    local tntexp = require 'fbcode.deeplearning.experimental.yuandong.torchnet.init'

    -- time one iteration
    tntexp.TimeMeter{ rack = rack, label = "time", perbatch = true }
end

function nnutils.set_output_json(log, trainer, config)
    local epoch = 1
    local entries_to_log = {'trainloss', 'testloss', 'train top@1', 'train top@5', 'test top@1', 'test top@5' }

    trainer:addHook(
       'end-epoch',
       function()
          -- Save a few things to json
          local perf_table = { epoch = epoch }
          for _, entry in ipairs(entries_to_log) do
            if log.key2idx[entry] then
                perf_table[entry] = log:get(entry)
            end
          end

          -- Entries for current time stamp
          perf_table.timestamp = os.clock()

          -- Special entry for whetlab (must be the last one)
          perf_table.neg_loss = -log:get("testloss")

          bistro.log(pl.tablex.merge(perf_table, config, true))
          epoch = epoch + 1
       end
    )    
end

function nnutils.add_save_on_trainer(log, net, trainer, saveto)
    -- customized model save
    log:column('saved')
    local netsav = net:clone('weight', 'bias', 'running_mean', 'running_std')
    local minerr = math.huge
    trainer:addHook(
       'end-epoch',
       function()
          local valid_col = nnutils.get_first_available(log.key2idx, { 'testloss', 'trainloss' } ) 
          local z = log:get(valid_col)
          if z and z < minerr then
             if pl.path.isdir(saveto) then
                savefile = string.format('%s/model.bin', saveto)
             else 
                savefile = saveto 
             end
             local f = torch.DiskFile(savefile, 'w')
             f:binary()
             f:writeObject(netsav)
             f:close()
             minerr = z
             log:set('saved', '*')
          else
             log:set('saved', '')
          end
       end
    )
end

function nnutils.add_logging(trainer, log)
    trainer:addHook(
       'end-epoch',
       function()
          log:print{}
          log:print{stdout = true, labels = true, separator = ' | '}
       end
    )
end

function nnutils.reload_if(config, model_name, config_name)
    -- reload?
    if config.evalOnly and config.reload == '' then
       error("evalOnly only works if there is a model to be reloaded!")
    end

    local net
    if config.reload ~='' then
       require 'nn'
       require 'cutorch'
       require 'cunn'
       require 'cudnn'
       print(string.format('| reloading experiment %s', config.reload))
       local f = torch.DiskFile(string.format('%s/%s', config.reload, model_name))
       f:binary()
       net = f:readObject()
       f:close()

       if config_name then
           local oldconfig_file = string.format('%s/%s', config.reload, config_name)
           if pl.path.exists(oldconfig_file) then
              local oldconfig = torch.load(oldconfig_file)
              oldconfig.subdir = nil
              tnt.utils.table.merge(oldconfig, config)
              oldconfig.reload = nil
              oldconfig.save = config.reload
              config = oldconfig
            end
       end
    end
    return net, config
end

--------------------------- Parse text to word table index ----------------------------

function nnutils.parse_to_idx(s, isfilename, word2index, per_char)
    local word_indices = {}
    -- Check the words 
    local sep = per_char and "." or "[^%s]+"

    local content 
    if isfilename then
       local f = torch.DiskFile(s)
       content = f:readString('*a') -- NOTE: this reads the whole file at once
       print(string.format("size of content = %d", string.len(content)))
       f:close()
    else 
       content = s
    end

    for token in string.gmatch(content, sep) do
        local index = word2index[token]
        if index ~= nil then 
          table.insert(word_indices, index) 
        end
    end
    print(string.format("Number of tokens = %d", #word_indices))

    return word_indices
end

function nnutils.split_seq_into_batch(data, batch_size, seq_length)
    -- Cut them into batches. 
    local len = data:size(1)
    local xdata, ydata

    if len % (batch_size * seq_length) ~= 0 then
       print('cutting off end of data so that the batches/sequences divide evenly')
       xdata = data:sub(1, batch_size * seq_length * math.floor(len / (batch_size * seq_length)))
    else 
       xdata = data
    end

    local ydata = xdata:clone()
    ydata:sub(1,-2):copy(xdata:sub(2,-1))
    ydata[-1] = xdata[1]

    local x_batches = xdata:view(batch_size, -1):split(seq_length, 2)  -- #rows = #batches
    local y_batches = ydata:view(batch_size, -1):split(seq_length, 2)  -- #rows = #batches
    assert(#x_batches == #y_batches)

    return x_batches, y_batches
end

---------------------------　Deal with configurations ----------------------------------
function nnutils.get_config(default_config)
  local config = bistro.get_params(nnutils.add_if_nonexist(default_config, 
      { lr = 0.05, gpu = 1, seed = 1111, nthread = 8, evalOnly = false, 
        train_batch = 128, test_batch = 128, max_epoch = 100, reload = '', save = './'}))

  -- reload?
  if config.evalOnly and config.reload == '' then
     error("evalOnly only works if there is a model to be reloaded!")
  end

  local net
  if config.reload ~= '' then
     require 'nn'
     require 'cutorch'
     require 'cunn'
     require 'cudnn'
     print(string.format('| reloading experiment %s', config.reload))
     if pl.path.isdir(config.reload) then
        loadfilename = string.format('%s/model.bin', config.reload)
     else 
        loadfilename = config.reload
     end
     local f = torch.DiskFile(loadfilename)
     f:binary()
     net = f:readObject()
     f:close()

     local oldconfig_file = string.format('%s/config.bin', config.reload)
     if pl.path.exists(oldconfig_file) then
        local oldconfig = torch.load(oldconfig_file)
        oldconfig.subdir = nil
        tnt.utils.table.merge(oldconfig, config)
        oldconfig.reload = nil
        oldconfig.save = config.reload
        config = oldconfig
     end

  end

  -- execute lua code in command line with config as environmentß
  -- tnt.utils.sys.cmdline(arg, config)
  print(pl.pretty.write(config))

  return config, net
end

--------------------------　Simple Torchnet framework ----------------------------------
function nnutils.torchnet_custom_merge()
  local transform = require 'torchnet.transform'
  local utils = require 'torchnet.utils'
  return transform.tableapply(
    function (field)
      if type(field) == 'table' and field[1] then
        if type(field[1]) == 'number' then
          return torch.Tensor(field)
        elseif torch.typename(field[1]) and torch.typename(field[1]):match('Tensor') then
          return utils.table.mergetensor(field)
        end
      end
      return field
    end)
end

local function old_wrap_dataset(dataset_closure, nthread, nbatch)
  local tntexp = require('fbcode.deeplearning.experimental.yuandong.torchnet.init')
  if nthread == 0 then
    -- return tnt.CudaDataset(tnt.BatchDataset{ dataset = dataset_closure(), batchsize = nbatch })
    return tntexp.CudaDataset(dataset_closure())
  else 
    -- local dataset_closure_local = dataset_closure 
    -- local batch_closure = function () 
    --     return tnt.BatchDataset{ dataset = dataset_closure_local(), batchsize = nbatch } 
    -- end
    return tntexp.CudaDataset(tntexp.ParallelDataset{
        nthread = nthread,
        closure = dataset_closure
    })
  end
end

function nnutils.run_old_torchnet(train, test, net, crit_type, config)
    local tntexp = require('fbcode.deeplearning.experimental.yuandong.torchnet.init')

    net = net:cuda()

    local crit
    if crit_type == "classification" then
       crit = nn.ClassNLLCriterion()
    elseif crit_type == "reconstruction" then
       crit = nn.MSECriterion()
    end
    crit = crit:cuda()

    config.logger_filename = config.logger_filename or string.format('%s/log', config.save)
    config.model_filename = config.model_filename or string.format("%s/model.bin", config.save)

    local log = tntexp.Logger{ filename = config.logger_filename }

    local trainer = tntexp.SGDTrainer(log)
    nnutils.add_regular_hooks(trainer, crit)
    -- check the average criterion value
    tntexp.AverageValueMeter{ rack = trainer, eval = function() return crit.output end, label = "trainloss" }
    if crit_type == "classification" then
        tntexp.ClassErrorMeter{ rack = trainer, eval = function() return net.output end, topk = {5,1}, label = "train" }  
    end


    -- log
    -- trainer:addHook(
    --    'sample',
    --    function(sample)
    --       print(sample)
    --    end
    -- )

    -- tester
    if test then 
       local tester = tntexp.SGDTester(log)
       nnutils.add_regular_hooks(tester, crit)

       tntexp.AverageValueMeter{ rack = tester, eval = function() return crit.output end, label = "testloss" }
       if crit_type == "classification" then
          tntexp.ClassErrorMeter{ rack = tester, eval = function() return net.output end, topk = {5,1}, label = "test" }  
       end

       -- we hook it to the trainer
       tester:test{
           network = net,
           dataset = old_wrap_dataset(test, config.nthread, config.test_batch), 
           rack = trainer
       }
    end

    -- customized model save
    nnutils.add_save_on_trainer(log, net, trainer, config.model_filename)

    -- log
    -- Note that this has to be put in the last, otherwise since the statistics are not fully collected, it will error.
    trainer:addHook(
       'end-epoch',
       function()
          log:print{}
          log:print{stdout = true, labels = true, separator = ' | '}
       end
    )

    -- go
    log:header{}

    trainer:train{
       network = net,
       criterion = crit,
       dataset = old_wrap_dataset(train, config.nthread, config.train_batch), 
       lr = config.lr,
       maxepoch = config.max_epoch
    }
    return log
end


local function wrap_dataset(dataset_closure, nthread)
  local tnt = require('torchnet')
  if nthread == 0 then
    -- return tnt.CudaDataset(tnt.BatchDataset{ dataset = dataset_closure(), batchsize = nbatch })
    return tnt.DatasetSampler(dataset_closure())
  else 
    -- local dataset_closure_local = dataset_closure 
    -- local batch_closure = function () 
    --     return tnt.BatchDataset{ dataset = dataset_closure_local(), batchsize = nbatch } 
    -- end
    local dataset = tnt.ParallelDatasetSampler{
        nthread = nthread,
        closure = dataset_closure
    }

    return dataset
  end
end

function nnutils.run_torchnet(train, test, net, crit_type, config)
    local tnt = require('torchnet')

    nnutils.dprint("Put network to cuda")
    net = net:cuda()

    local crit
    if crit_type == "classification" then
       crit = nn.ClassNLLCriterion()
    elseif crit_type == "reconstruction" then
       crit = nn.MSECriterion()
    end

    nnutils.dprint("Put crit to cuda")
    crit = crit:cuda()

    config.logger_filename = config.logger_filename or string.format('%s/log', config.save)
    config.model_filename = config.model_filename or string.format("%s/model.bin", config.save)

    local log = tnt.Logger{ filename = config.logger_filename }

    local engine = tnt.SGDEngine()

    -- time one iteration
    local timer = tnt.TimeMeter{ per = true }

    -- check the average criterion value
    local trainloss = tnt.AverageValueMeter()
    local testloss = tnt.AverageValueMeter()
    local trainerr = tnt.ClassErrorMeter{ topk = {5,1} }
    local testerr = tnt.ClassErrorMeter{ topk = {5,1} }
    local saved = false

    local log_terms = {
        timer = function () return timer:value()*1000 end,
        trainloss = function () return trainloss:value() end, 
        -- testloss = function () return testloss:value() end,
        trainerr1 = function () return trainerr:value(1) end, 
        testerr1 = function () return testerr:value(1) end,
        trainerr5 = function () return trainerr:value(5) end, 
        testerr5 = function () return testerr:value(5) end, 
        saved = function () return saved and '*' or ' ' end
    }

    -- customized model save
    -- we save a stateless model
    local netsav = net:clone('weight', 'bias')
    local minerr = math.huge

    local train_wrapper = wrap_dataset(train, config.nthread)
    local test_wrapper = wrap_dataset(test, config.nthread)

    -- print(train_wrapper)
    -- print("Net type = ")

    -- print(torch.typename(net))
    -- print("Crit type = ")

    -- print(torch.typename(crit))
    -- print("TrainWrapper type = ")
    -- print(torch.typename(train_wrapper))

    -- print("Lr type = ")
    -- print(type(config.lr))

    -- print("max_epoch type = ")

    -- print(type(config.max_epoch))

    -- local class = require 'class'
    -- local env = require 'argcheck.env'

    -- print(env.istype(net, 'nn.Module'))
    -- print(env.istype(crit, 'nn.Criterion'))
    -- print(env.istype(train_wrapper, 'tnt.DatasetSampler'))
    -- print(env.istype(config.lr, 'number'))
    -- print(class.type(train_wrapper))

    for event, state in
       engine:train{ network = net, criterion = crit, sampler = train_wrapper, 
                     lr = config.lr, maxepoch = config.max_epoch } do
        if event == 'start-epoch' then
--             print("nnutils.run_torchnet: In start-epoch!")
             trainloss:reset()
             trainerr:reset()
             timer:reset()
             timer:resume()
        elseif event == 'update' then
--             print("nnutils.run_torchnet: In update!")

             trainloss:add(state.criterion.output)
             trainerr:add(state.network.output, state.sample.target)
             cutorch.synchronize()
             collectgarbage()
             timer:inc()
        elseif event == 'end-epoch' then
--             print("nnutils.run_torchnet: In end-epoch!")

             timer:stop()

             -- test
             for event, state in engine:test{ network = net, sampler = test_wrapper } do
                if event == 'start-epoch' then
                   testerr:reset()
                   -- testloss:reset()
                elseif event == 'forward' then
                   collectgarbage()
                   -- testloss:add(state.criterion.output)
                   testerr:add(state.network.output, state.sample.target)
                end
             end

             -- save if better than ever
             local z = testerr:value(1)
             if z < minerr then
                local f = torch.DiskFile(config.model_filename, 'w')
                f:binary()
                f:writeObject(netsav)
                f:close()
                minerr = z
                saved = true
             else 
                saved = false
             end
             -- spit out log
             local messages = { string.format(" epoch: %d", state.epoch) }
             for k, v in pairs(log_terms) do
                 local value = v()
                 if type(value) == 'number' then 
                    if value == math.ceil(value) then
                      value = string.format("%d", value)
                    else
                      value = string.format("%.2f", value) 
                    end
                 end
                 table.insert(messages, string.format("%s: %s", k, value))
             end
             log:print(table.concat(messages, " | "))
          end
    end
    return log_terms
    -- return log
end

--------------------------- Remove batch normalization ---------------------------------

local function merge_layer(bn, linear)
   if bn == nil or linear == nil then return end

   local bn_matched = (torch.type(bn) == "nn.SpatialBatchNormalization" or torch.type(bn) == "nn.BatchNormalization")
   local linear_matched = (torch.type(linear) == "cudnn.SpatialConvolution" or torch.type(linear) == "nn.Linear")

   assert(not bn_matched or linear_matched, "Find BatchNormalization layer but linear layer is missing!")
   if (not bn_matched) or (not linear_matched) then return end

   --[[ 
    linear.weight = channelo * channeli * kh * kw
    linear.bias = channelo
    bn.weight = channelo
    bn.bias = channelo
    bn.running_mean = channelo
    bn.running_std = channelo
   --]]
   -- Note that running_std is the inverse of std.
   local device_id = bn.running_mean:getDevice()
   cutorch.withDevice(device_id, 
       function () 
           local scale = bn.running_std:clone()
           local shift = bn.running_mean:clone()

           scale:cmul(bn.weight)
           shift:cmul(scale):mul(-1.0):add(bn.bias)

           for i = 1, linear.weight:size(1) do
               linear.weight[i]:mul(scale[i])
           end
           linear.bias:cmul(scale):add(shift)
   end)

   return linear
end

local function recursive_merge_layer(model)
    local prev_mod
    for i = 1, #model.modules do
        local mod = model.modules[i]
        if mod.modules then
          recursive_merge_layer(mod)
        else
          merge_layer(mod, prev_mod)
        end
        prev_mod = mod
    end
end

local function rebuild_layers_except(old_model, except_mod_names)
    if old_model.modules then
        local new_model = old_model:clone()
        new_model.modules = {}

        for i = 1, #old_model.modules do
            local layer = rebuild_layers_except(old_model.modules[i], except_mod_names)
            if layer ~= nil then new_model:add(layer) end
        end
        return new_model
    else
        if pl.tablex.find(except_mod_names, torch.type(old_model)) == nil then 
            return old_model 
        end
    end
end

function nnutils.remove_batchnorm(model)
    -- Actual convert the model.
    recursive_merge_layer(model)
    -- Remove batch normalization layers by rebuild the model
    return rebuild_layers_except(model, { "nn.BatchNormalization", "nn.SpatialBatchNormalization" })
end

---------------------------- Remove all data parallel parallel ---------------------

local function remove_data_parallel(model)
  local res = {}
  for i, m in ipairs(model.modules) do
    if torch.typename(m) == 'nn.DataParallel' then
      table.insert(res, remove_data_parallel(m.modules[1]))
    else
      table.insert(res, m:clone())
    end
  end

  local new_model = model:clone()
  new_model.modules = res
  return new_model
end

nnutils.remove_data_parallel = remove_data_parallel

---------------------------- Convert between different permutations of classes ---------------------

local function load_list(f)
  if type(f) ~= 'string' then return f end

  local ext = pl.path.extension(f) 
  if ext == '.t7' then 
    return torch.load(f)
  elseif ext == '.lst' then
    return (require 'torchnet.utils.sys').loadlist(f, true)
  end
end

function nnutils.classconverter(sourcefile, targetfile, name_converter)
  local src = load_list(sourcefile)
  local dst = load_list(targetfile)

  local dst_inv = {}
  for i, v in ipairs(dst) do
    dst_inv[v] = i
  end

  return function (srcidx) 
    if type(srcidx) == 'number' then
      return dst_inv[name_converter(src[srcidx])] 
    elseif type(srcidx) == 'table' then
      local res = {}
      for _, i in ipairs(srcidx) do
         table.insert(res, dst_inv[name_converter(src[i])])
      end
      return res
    elseif torch.typename(srcidx) == 'torch.DoubleTensor' then
      local res = torch.DoubleTensor(srcidx:size())
      for i = 1, res:nElement() do
        res[i] = dst_inv[name_converter(src[i])]
      end
      return res
    end
  end
end

------------------ Compute the prediction ------------------
--- Top one accuracy

function nnutils.predict_compare(model, s)
  model:evaluate()
  local data_cuda = s.input:cuda()
  local res = model:forward(data_cuda)
  local max_value, max_indices = torch.max(res:float(), 2)

  local accuracy = s.target:long():eq(max_indices:long()):sum() / s.input:size(1)
  return max_indices, accuracy
end

-- Predict the top k error
-- s.input is the data, s.target is the label, topk = { 1, 3, 5} e.g.
function nnutils.predict_top(model, s, topk)
  model:evaluate()
  local data_cuda = s.input:cuda()
  local output = model:forward(data_cuda)

  local sum = {}
  local maxk = 0
  for _,k in ipairs(topk) do
    sum[k] = 0
    maxk = math.max(maxk, k)
  end
  local _, pred = output:double():sort(2, true)
  local no = output:size(1)
  for i=1,no do
    local predi = pred[i]
    local targi = s.target[i]
    local minik = math.huge
    for k=1,maxk do
       if predi[k] == targi then
          minik = k
          break
       end
    end
    for _,k in ipairs(topk) do
       if minik > k then
          sum[k] = sum[k]+1
       end
    end
  end

  for _, k in ipairs(topk) do
      sum[k] = sum[k] / no
  end

  return sum
end

------------------------------ Misc ---------------------------------------
-- Check layers with given name in net1 and net2, and skip any difference caused by bn sign.
function nnutils.compare_network_skip_bn_upto_sign(net1, net2, layername)
   local i = 1
   local j = 1

   print(string.format("#net1.modules = %d", #net1.modules))
   print(string.format("#net2.modules = %d", #net2.modules))

   while true do
     print("i = ", i)
     print("j = ", j)

     while i <= #net1.modules do
        if torch.type(net1.modules[i]) ~= layername then i = i + 1 else break end
     end
     if i > #net1.modules then break end

     while j <= #net2.modules do
        if torch.type(net2.modules[j]) ~= layername then j = j + 1 else break end
     end
     if j > #net2.modules then break end

     -- Compare their parameters
     local w1 = net1.modules[i]:parameters()
     local w2 = net2.modules[j]:parameters()
     if #w1 ~= #w2 then 
        print("compare_network_skip_bn_upto_sign: Dimension mismatch.")
        print(string.format("net1.modules[%d] = ", i))
        print(#w1)
        print(string.format("net2.modules[%d] = ", j))
        print(#w2)
        error("")
     end

     for k = 1, #w1 do
       local s1 = w1[k]:storage()
       local s2 = w2[k]:storage()

       for l = 1, s1:size() do
          if math.abs(math.abs(s1[l]) - math.abs(s2[l])) > 1e-4 then
            error(string.format("Weight net1.modules[%d][%d][%d] (= %f) is different from net2.modules[%d][%d][%d] (= %f)", i, k, l, s1[l], j, k, l, s2[l]))
          end
       end
     end

     i = i + 1
     j = j + 1
   end
end

return nnutils
