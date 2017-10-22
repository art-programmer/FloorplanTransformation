local Print, parent = torch.class('nn.Print', 'nn.Module')

function Print:__init()
    parent.__init(self)
end

function Print:updateOutput(input)
    print(#input)
    print(input[1])
    self.output = input
    return self.output
end

function Print:updateGradInput(input, gradOutput)
    self.gradInput = gradOutput 
    return self.gradInput
end

function Print:__tostring__()
   return string.format('%s()', torch.type(self))
end
