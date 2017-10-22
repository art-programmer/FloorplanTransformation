--[[
    Input: A length-2 table of length-K tables
    Input[1]: K tables
    Input[2]: K tables

    Output: A length-K table of length-2 tables
    Output[i]: {Input[1][i], input[2][i]}
--]]

local CrossMergeTable, parent = torch.class('nn.CrossMergeTable', 'nn.Module')

function CrossMergeTable:__init()
    parent.__init(self)

    self.gradInput = {}
end

function CrossMergeTable:updateOutput(input)
    assert(#input == 2)
    assert(#input[1] == #input[2])

    self.output = {}
    for i = 1, #input[1] do
        self.output[i] = {input[1][i], input[2][i]}
    end
    return self.output
end

function CrossMergeTable:updateGradInput(input, gradOutput)
   for i = 1, 2 do 
      if not self.gradInput[i] then
         self.gradInput[i] = {}
      end
   end
  
   for i = 1, #gradOutput do
        self.gradInput[1][i] = gradOutput[i][1]
        self.gradInput[2][i] = gradOutput[i][2]
    end
    return self.gradInput
end

function CrossMergeTable:__tostring__()
   return string.format('%s()', torch.type(self))
end
