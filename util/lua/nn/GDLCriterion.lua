local GDLCriterion, parent = torch.class('nn.GDLCriterion', 'nn.Criterion')

function GDLCriterion:__init(alpha, sizeAverage)

  parent.__init(self)
  self.alpha = alpha or 1
  self.sizeAverage = sizeAverage or true

  assert(self.alpha == 1 or self.alpha == 2, "alpha should be 1 or 2")

  local hNet = nn.Sequential()
  hNet:add(nn.ConcatTable():add(nn.Narrow(3, 1, -2)):add(nn.Narrow(3, 2, -1)))
  hNet:add(nn.CSubTable()):add(nn.Abs())
  local wNet = nn.Sequential()
  wNet:add(nn.ConcatTable():add(nn.Narrow(4, 1, -2)):add(nn.Narrow(4, 2, -1)))
  wNet:add(nn.CSubTable()):add(nn.Abs())

  self.inputNet = nn.ConcatTable():add(hNet):add(wNet)
  self.targetNet = self.inputNet:clone()

  self.criterion = {}
  if self.alpha == 1 then
    self.criterion[1] = nn.AbsCriterion(self.sizeAverage)
    self.criterion[2] = nn.AbsCriterion(self.sizeAverage)
  else
    self.criterion[1] = nn.MSECriterion(self.sizeAverage)
    self.criterion[2] = nn.MSECriterion(self.sizeAverage)
  end

end

function GDLCriterion:updateOutput(input, target)

  assert( input:nElement() == target:nElement(),
  "input and target size mismatch")

  self.inputNetOutput = self.inputNet:forward(input)
  self.targetNetOutput = self.targetNet:forward(target)

  self.output = self.criterion[1]:forward(self.inputNetOutput[1], self.targetNetOutput[1])
  self.output = self.output + self.criterion[2]:forward(self.inputNetOutput[2], self.targetNetOutput[2])

  return self.output

end

-- must have called updateOutput with the same input/target pair right before
function GDLCriterion:updateGradInput(input, target)

  assert( input:nElement() == target:nElement(),
  "input and target size mismatch")

  local gradCriterion = {}
  gradCriterion[1] = self.criterion[1]:backward(self.inputNetOutput[1], self.targetNetOutput[1])
  gradCriterion[2] = self.criterion[2]:backward(self.inputNetOutput[2], self.targetNetOutput[2])
  
  self.gradInput = self.inputNet:backward(input, gradCriterion)
  
  return self.gradInput

end
