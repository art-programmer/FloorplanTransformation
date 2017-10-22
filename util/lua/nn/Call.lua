local Call, parent = torch.class('nn.Call', 'nn.Module')

function Call:__init(func, gradFunc)
    parent.__init(self)
    self.func = func or function (x) return x end
    self.gradFunc = gradFunc or function (x, y) return x end
end

function Call:updateOutput(input)
    self.output = self.func(input)
    return self.output
end

function Call:updateGradInput(input, gradOutput)
    self.gradInput = self.gradFunc(input, gradOutput)
    return self.gradInput
end

function Call:__tostring__()
   return string.format('%s()', torch.type(self))
end
