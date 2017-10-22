------------------------------------------------------------------------
--[[ VRRegressReward ]]--
-- Variance reduced regression reinforcement criterion.
-- input : {prediction, baseline reward}
-- Reward is 1 - x, where x is the MSE between predicted and GT pixels
-- reward = scale*(Reward - baseline) where baseline is 2nd input element
-- Note : for RNNs with R = 1 for last step in sequence, encapsulate it
-- in nn.ModuleCriterion(VRRegressReward, nn.SelectTable(-1))
------------------------------------------------------------------------
local VRRegressReward, parent = torch.class("nn.VRRegressReward", "nn.Criterion")

function VRRegressReward:__init(module, scale, rho, criterion)
  parent.__init(self)
  self.module = module -- so it can call module:reinforce(reward)
  self.scale = scale or 1 -- scale of reward
  self.rho = rho or 1 -- recurrent iterations
  self.criterion = criterion or nn.MSECriterion() -- baseline criterion
  self.sizeAverage = true
end

function VRRegressReward:updateOutput(inputTable, target)
  assert(torch.type(inputTable) == 'table')
  local input = self:toBatch(inputTable[1], 1)
  local baseline = self:toBatch(inputTable[2], 1)
  assert((#input)[1] * self.rho == (#baseline)[1])

  -- reward = MSE between predicted and GT pixels
  local diff = (input - target):pow(2):mul(-self.scale)
  self.reward = self.reward or baseline.new()
  self.reward:resize((#baseline)[1])
  for i = 1, (#input)[1] do
    self.reward[{{(i - 1) * self.rho + 1, i * self.rho}}] = diff[i]:mean()
  end

  -- loss = -sum(reward)
  self.output = -self.reward:sum()
  if self.sizeAverage then
    self.output = self.output/(#baseline)[1]
  end
  return self.output
end

function VRRegressReward:updateGradInput(inputTable, target)
  local input = self:toBatch(inputTable[1], 1)
  local baseline = self:toBatch(inputTable[2], 1)

  -- reduce variance of reward using baseline
  self.vrReward = self.vrReward or self.reward.new()
  self.vrReward:resizeAs(self.reward):copy(self.reward)
  self.vrReward:add(-1, baseline)
  if self.sizeAverage then
    self.vrReward:div(input:size(1))
  end
  -- broadcast reward to modules
  self.module:reinforce(self.vrReward)  

  -- zero gradInput (this criterion has no gradInput for prediction)
  self.gradInput = self.gradInput or {}
  self.gradInput[1] = self.gradInput[1] or input.new()
  self.gradInput[1]:resizeAs(input):zero()
  self.gradInput[1] = self:fromBatch(self.gradInput[1], 1)

  -- learn the baseline reward
  self.gradInput[2] = self.criterion:backward(baseline, self.reward)
  self.gradInput[2] = self:fromBatch(self.gradInput[2], 1)
  return self.gradInput
end

function VRRegressReward:type(type)
  self._maxVal = nil
  self._maxIdx = nil
  self._target = nil
  local module = self.module
  self.module = nil
  local ret = parent.type(self, type)
  self.module = module
  return ret
end
