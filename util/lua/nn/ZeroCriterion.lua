local ZeroCriterion, parent = torch.class('nn.ZeroCriterion', 'nn.Criterion')

function ZeroCriterion:__init()
    parent.__init(self)
end

function ZeroCriterion:updateOutput(input, target)
  self.output = 0
  return self.output
end

local function retable(x, y)
  if type(y) == 'table' then
    x = type(x) == 'table' and x or {}
    for k, v in ipairs(y) do
      x[k] = retable(x[k], v)
    end
    for i = #y + 1, #x do
      x[i] = nil
    end
  else
    x = type(x) == 'userata' and x or y.new()
    x:resizeAs(y):fill(0)
  end

  return x
end

function ZeroCriterion:updateGradInput(input, target)
  -- for lua pass by ref
  self.gradInput = retable(self.gradInput, input)
  return self.gradInput
end

