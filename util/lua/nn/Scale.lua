--[[
    Input: A length-2 Table
    Input[1]: Responses, batchSize x nChannels x iH x iW
    Input[2]: Pairs (minW, minH, maxW, maxH), batchSize x 2 x 2

    Output: Scaled responses with zero paddings
            batchSize x nChannels x iH x iW
--]]
require 'image'

local Scale, parent = torch.class('nn.Scale', 'nn.Module')

function Scale:__init(sum)
    parent.__init(self)

    self.sum = sum
    self.gradInput = {}
end


function Scale:updateOutput(input)
    assert(#input == 2)
    assert(input[1]:size(1) == input[2]:size(1))

    local batchSize = input[1]:size(1)
    local nChannels = input[1]:size(2)
    local iH = input[1]:size(3)
    local iW = input[1]:size(4)
    self.output:resize(batchSize, nChannels, iH, iW):zero()
    
    self.buffer = self.buffer or input[1].new()
    self.buffer:resize(batchSize, nChannels)

    for i = 1, batchSize do
        local minW = input[2][i][1][1]
        local minH = input[2][i][1][2]
        local maxW = input[2][i][2][1]
        local maxH = input[2][i][2][2]
        local ratio = (maxW - minW + 1) * (maxH - minH + 1) / (iW * iH)

        self.output[{i, {}, {minH, maxH}, {minW, maxW}}] = toNNTensor(
            image.scale(input[1][i]:double(), maxW - minW + 1, maxH - minH + 1)):mul(1/ratio)
----[[
        for j = 1, nChannels do
            if self.output[i][j]:sum() == 0 then
                self.buffer[i][j] = 0
            else
                self.buffer[i][j] = math.min(self.sum / self.output[i][j]:sum(), 100)
                self.output[i][j]:mul(self.buffer[i][j])
            end
            if self.output[i][j]:ne(self.output[i][j]):sum() > 0 then
                print(self.buffer[i][j])
                print(i..' '..j)
                print('!!!!!!!!!!!!!!!!!!!!!!! Found NaN in output !!!!!!!!!!!!!!!!!!!!!!!')
            end
        end
--[[
        print(i..' input sum: '..input[1][i]:sum())
        print(i..' output sum: '..self.output[i]:sum())
--]]
    end
    
    return self.output
end

function Scale:updateGradInput(input, gradOutput)
    for i = 1, #input do 
        if self.gradInput[i] == nil then
            self.gradInput[i] = input[i].new()
        end
        self.gradInput[i]:resizeAs(input[i]):zero()
    end

    local batchSize = input[1]:size(1)
    local nChannels = input[1]:size(2)
    local iH = input[1]:size(3)
    local iW = input[1]:size(4)
    
    for i = 1, batchSize do
        local minW = input[2][i][1][1]
        local minH = input[2][i][1][2]
        local maxW = input[2][i][2][1]
        local maxH = input[2][i][2][2]
        local ratio = (maxW - minW + 1) * (maxH - minH + 1) / (iW * iH)

        self.gradInput[1][i] = toNNTensor(image.scale(
            gradOutput[{i, {}, {minH, maxH}, {minW, maxW}}]:double(), iW, iH))--:mul(ratio)

----[[
        for j = 1, nChannels do
            self.gradInput[1][i][j]:mul(self.buffer[i][j])
        end
--]]    
    end
    
    return self.gradInput
end

function Scale:__tostring__()
   return string.format('%s()', torch.type(self))
end
