local CrossConvolveParallel, parent = torch.class('nn.CrossConvolveParallel', 'nn.Module')

function CrossConvolveParallel:__init(nInputPlane, nOutputPlane, kW, kH)
   parent.__init(self)

   kH = kH or kW

   -- get args
   self.nInputPlane = nInputPlane or 1
   self.nOutputPlane = nOutputPlane or 1
   self.kW = kW
   self.kH = kH

   -- padding values
   self.padH = math.floor(kH / 2)
   self.padW = math.floor(kW / 2)

   self.convolver = {}

   self.gradInput = {}
end

function CrossConvolveParallel:updateOutput(input)
   assert(input[2]:size(5) == self.kH)
   assert(input[2]:size(4) == self.kW)

   -- Create convolver
   if #self.convolver < input[1]:size(1) then
       for i=1,input[1]:size(1) do 
           local convolver = nn.Sequential()
           convolver:add(nn.SpatialZeroPadding(self.padW, self.padW, self.padH, self.padH))
           convolver:add(nn.SpatialConvolution(self.nInputPlane, self.nOutputPlane, self.kW, self.kH))
           
           -- set bias
           convolver.modules[2].bias:zero()
           if self:type() == 'torch.CudaTensor' then
               convolver:cuda()
           end

           -- Add to list
           table.insert(self.convolver, convolver)
       end
   end

   -- compute output
   local nSample = input[2]:size(1)
   for i=1,nSample do
       self.convolver[i].modules[2].weight = input[2][i]
       local tmp = self.convolver[i]:updateOutput(input[1][i])
       if (self.output == nil) or (self.output:size():size()==0) or (self.output:size(1)~=nSample) then
           local h = tmp:size(2)
           local w = tmp:size(3)
           if self:type() == 'torch.CudaTensor' then
               self.output = torch.CudaTensor(nSample,self.nOutputPlane,h,w)
           else
               self.output = torch.DoubleTensor(nSample,self.nOutputPlane,h,w)
           end
       end
       self.output[i] = tmp 
   end

   -- done
   return self.output
end

function CrossConvolveParallel:updateGradInput(input, gradOutput)
   -- resize grad
   for i = 1, #input do 
      if self.gradInput[i] == nil then
         self.gradInput[i] = input[i].new()
      end
      self.gradInput[i]:resizeAs(input[i]):zero()
   end

   -- backprop
   for i = 1, input[1]:size(1) do
       self.convolver[i]:zeroGradParameters()
       self.gradInput[1][i]:add(self.convolver[i]:updateGradInput(input[1][i], gradOutput[i]))
       self.convolver[i]:accGradParameters(input[1][i], gradOutput[i])
       self.gradInput[2][i]:add(self.convolver[i].modules[2].gradWeight)
   end

   -- done
   return self.gradInput
end

function CrossConvolveParallel:clearState()
   self.convolver:clearState()
   return parent.clearState(self)
end

function CrossConvolveParallel:__tostring__()

    return torch.type(self) .. string.format(' (%dx%dx%dx%d)', 
        self.nInputPlane, self.nOutputPlane, self.kW, self.kH)

end





