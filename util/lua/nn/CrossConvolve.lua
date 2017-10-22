local CrossConvolve, parent = torch.class('nn.CrossConvolve', 'nn.Module')

function CrossConvolve:__init(nInputPlane, kW, kH)
   parent.__init(self)

   kH = kH or kW

   -- get args
   self.nInputPlane = nInputPlane or 1
   self.kW = kW
   self.kH = kH

   -- padding values
   self.padH = math.floor(kH / 2)
   self.padW = math.floor(kW / 2)

   -- create convolver
   self.convolver = nn.Sequential()
   self.convolver:add(nn.SpatialZeroPadding(self.padW, self.padW, self.padH, self.padH))
   self.convolver:add(nn.SpatialConvolution(self.nInputPlane, 1, kW, kH))
   
   -- set bias
   self.convolver.modules[2].bias:zero()
    
   self.gradInput = {}
end

function CrossConvolve:updateOutput(input)   
   assert(input[2]:size(1) == self.kH)
   assert(input[2]:size(2) == self.kW)

   for i = 1, self.nInputPlane do 
      self.convolver.modules[2].weight[1][i] = input[2]
   end
   
   -- compute output
   self.output = self.convolver:updateOutput(input[1])

   -- done
   return self.output
end

function CrossConvolve:updateGradInput(input, gradOutput)
   -- resize grad
   for i = 1, #input do 
      if not self.gradInput[i] then
         self.gradInput[i] = input[i].new()
      end
      self.gradInput[i]:resizeAs(input[i]):zero()
   end
   self.convolver:zeroGradParameters()

   -- backprop 
   self.gradInput[1]:add(self.convolver:updateGradInput(input[1], gradOutput))
   self.convolver:accGradParameters(input[1], gradOutput)
   for i = 1, self.nInputPlane do
       self.gradInput[2]:add(self.convolver.modules[2].gradWeight[1][i])
   end

   -- done
   return self.gradInput
end

function CrossConvolve:clearState()
   self.convolver:clearState()
   return parent.clearState(self)
end
