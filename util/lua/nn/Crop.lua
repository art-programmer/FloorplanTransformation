--[[
    Input: A length-2 Table
    Input[1]: Responses, batchSize x nChannels x iH x iW
    Input[2]: Pairs (minW, minH), batchSize x nFeatures x 2

    Output: Cropped responses, batchSize x (nFeatures x nChannels) x oH x oW
--]]

local Crop, parent = torch.class('nn.Crop', 'nn.Module')

function Crop:__init(iW, iH, oW, oH)
    parent.__init(self)

    self.iW = iW
    self.iH = iH
    self.oW = oW
    self.oH = oH

    self.gradInput = {}
    --self.vis = false
end

function Crop:getCoordinates()
    return self.coords
end

function Crop:updateOutput(input)
    assert(#input == 2)
    assert(input[1]:size(1) == input[2]:size(1))
    assert(input[1]:size(3) == self.iH)
    assert(input[1]:size(4) == self.iW)

    local batchSize = input[1]:size(1)
    local nChannels = input[1]:size(2)
    local nFeatures = input[2]:size(2)

--[[if self.vis then
    for k = 1, math.min(5, nChannels) do
        image.save('/home/jiajunwu/public_html/vis_results_11feat/CAS/crop_input_'..k..'.png', input[1][{1, k, {}, {}}]:double()) 
    end
end
    --]]
    self.output:resize(batchSize, nChannels * nFeatures, self.oH, self.oW)
    for p = 1, batchSize do
        for q = 1, nFeatures do
            local idxSt = (q - 1) * nChannels + 1
            local idxEd = q * nChannels
            self.output[{p, {idxSt, idxEd}, {}, {}}]:copy(input[1][{p, {}, 
                {input[2][{p, q, 1}], input[2][{p, q, 1}] + self.oH - 1}, 
                {input[2][{p, q, 2}], input[2][{p, q, 2}] + self.oW - 1}}])
        end
    end
--[[
if self.vis then
    for r = 1, nFeatures do 
        for k = 1, math.min(5, nChannels) do
            image.save('/home/jiajunwu/public_html/vis_results_11feat/CAS/crop_output_'..r..'chn'..k..'.png', self.output[{1, (r - 1) * nChannels + k, {}, {}}]:double()) 
        end
    end
end
self.vis = false
    --]]
    return self.output
end

function Crop:updateGradInput(input, gradOutput)
    for i = 1, #input do 
        if self.gradInput[i] == nil then
            self.gradInput[i] = input[i].new()
        end
        self.gradInput[i]:resizeAs(input[i]):zero()
    end

    local batchSize = input[1]:size(1)
    local nChannels = input[1]:size(2)
    local nFeatures = input[2]:size(2)
    
    for p = 1, batchSize do
        for q = 1, nFeatures do
            local idxSt = (q - 1) * nChannels + 1
            local idxEd = q * nChannels
            self.gradInput[1][{p, {}, {input[2][{p, q, 1}], input[2][{p, q, 1}] + self.oH - 1}, 
                {input[2][{p, q, 2}], input[2][{p, q, 2}] + self.oW - 1}}]:add(gradOutput[{p, {idxSt, idxEd}, {}, {}}])
        end
    end
    
    return self.gradInput
end

function Crop:__tostring__()
   return string.format('%s()', torch.type(self))
end
