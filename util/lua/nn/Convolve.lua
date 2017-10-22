local Convolve, parent = torch.class('nn.Convolve', 'nn.Module')

function Convolve:__init(nInputPlane, kernel)
   parent.__init(self)

   -- get args
   self.nInputPlane = nInputPlane or 1
   self.kernel = kernel or torch.Tensor(9,9):fill(1)
   local kdim = self.kernel:nDimension()

   -- check args
   if kdim ~= 2 and kdim ~= 1 then
      error('<Convolve> averaging kernel must be 2D or 1D')
   end

   -- padding values
   local padH = math.floor(self.kernel:size(1)/2)
   local padW = padH
   if kdim == 2 then
      padW = math.floor(self.kernel:size(2)/2)
   end

   -- create convolver
   self.convolver = nn.Sequential()
   self.convolver:add(nn.SpatialZeroPadding(padW, padW, padH, padH))
   if kdim == 2 then
      self.convolver:add(nn.SpatialConvolution(self.nInputPlane, 1, self.kernel:size(2), self.kernel:size(1)))
   else
      self.convolver:add(nn.SpatialConvolutionMap(nn.tables.oneToOne(self.nInputPlane), self.kernel:size(1), 1))
      self.convolver:add(nn.SpatialConvolution(self.nInputPlane, 1, 1, self.kernel:size(1)))
   end

   -- set kernel and bias
   if kdim == 2 then
      for i = 1,self.nInputPlane do 
         self.convolver.modules[2].weight[1][i] = self.kernel
      end
      self.convolver.modules[2].bias:zero()
   else
      for i = 1,self.nInputPlane do 
         self.convolver.modules[2].weight[i]:copy(self.kernel)
         self.convolver.modules[3].weight[1][i]:copy(self.kernel)
      end
      self.convolver.modules[2].bias:zero()
      self.convolver.modules[3].bias:zero()
   end
end

function Convolve:updateOutput(input)   
   -- compute output
   self.output = self.convolver:updateOutput(input)

   -- done
   return self.output
end

function Convolve:updateGradInput(input, gradOutput)
   -- resize grad
   self.gradInput:resizeAs(input):zero()

   -- backprop 
   self.gradInput:add(self.convolver:updateGradInput(input, gradOutput))

   -- done
   return self.gradInput
end

function Convolve:clearState()
   self.convolver:clearState()
   return parent.clearState(self)
end
