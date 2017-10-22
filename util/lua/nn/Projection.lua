grad = require 'autograd'
--[[
    Input: [AlphaScale, Alpha, F, Theta, Trans]
    Output: [X, Y], both projected to 2D space
--]]

local Projection, parent = torch.class('nn.Projection', 'nn.Module')

function Projection:__init(Bs, minParams, maxParams, w, numAlpha, numF, numTheta, numTrans, imW, imH)
    parent.__init(self)

    assert((#Bs)[1] == numAlpha)
    assert((#Bs)[2] == 3)

    self.Bs = Bs
    self.numPoints = self.Bs[1]:size(2)
    self.minParams = minParams
    self.maxParams = maxParams
    self.w = w
    
    self.numAlpha = numAlpha
    self.numF = numF or 1
    self.numTheta = numTheta or 6
    self.numTrans = numTrans or 2
    self.num3DParams = self.numAlpha + self.numF + self.numTheta + self.numTrans
    self.indF = self.numAlpha
    self.indR = self.indF + self.numF
    self.indT = self.indR + self.numTheta

    self.imW = imW or 240
    self.imH = imH or 320
end

local function updateScalarOutput(input, p, q, r, self)
    assert(r == 1 or r == 2)
   
    local scaled = {}
    for i = 1, self.num3DParams do
        scaled[i] = input[p][i] / self.w[i] * (self.maxParams[i] - self.minParams[i]) + self.minParams[i]
    end

    local sumB = scaled[1] * self.Bs[{1, {}, q}]
    for i = 2, self.numAlpha do
        sumB = sumB + scaled[i] * self.Bs[{i, {}, q}]
    end

    local S1 = scaled[self.indR + 1]
    local S2 = scaled[self.indR + 2]
    local S3 = scaled[self.indR + 3]
    local C1 = scaled[self.indR + 4]
    local C2 = scaled[self.indR + 5]
    local C3 = scaled[self.indR + 6]
    local X3D = C2 * C3 * sumB[1] - C2 * S3 * sumB[2] + S2 * sumB[3] + scaled[self.indT + 1]
    local Y3D = (S1 * S2 * C3 + C1 * S3) * sumB[1] + (-S1 * S2 * S3 + C1 * C3) * sumB[2] - S1 * C2 * sumB[3] + scaled[self.indT + 2]
    local Z3D = (-C1 * S2 * C3 + S1 * S3) * sumB[1] + (C1 * S2 * S3 + S1 * C3) * sumB[2] + C1 * C2 * sumB[3]

    -- input is finv
    local f = 1 / scaled[self.indF + 1]
    if r == 1 then
        return (f / (f + Z3D) * Y3D) / self.imH + 0.5
    else
        return (f / (f + Z3D) * X3D) / self.imW + 0.5
    end
end

function Projection:updateOutput(input)
    assert(input:size(2) == self.num3DParams)
    
    local batchSize = input:size(1)
    self.output:resize(batchSize, self.numPoints, 2)

    self.dnet = {}
    for p = 1, batchSize do
        self.dnet[p] = {}
        for q = 1, self.numPoints do
            self.dnet[p][q] = {}
            for r = 1, 2 do
                self.output[p][q][r] = updateScalarOutput(input, p, q, r, self)                
                if self.train then
                    self.dnet[p][q][r] = grad(updateScalarOutput)
                end
            end
        end
        --print(input[p])
        --print(self.output[p])
    end

    return self.output
end

function Projection:updateGradInput(input, gradOutput)
    local batchSize = input:size(1)
    assert(self.train == true, 'should be in training mode when self.train is true')
    assert(self.dnet, 'must call :updateOutput() first')

    self.gradInput:resizeAs(input):zero()

    for p = 1, batchSize do
        for q = 1, self.numPoints do
            for r = 1, 2 do
                local stepGrad = self.dnet[p][q][r](input, p, q, r, self) * gradOutput[p][q][r]
                if stepGrad:sum() ~= stepGrad:sum() then
                    print(p..' '..q..' '..r..' nan')
                end
                self.gradInput = self.gradInput + stepGrad 
            end
        end
    end
   
    if self.gradInput:min() < -10 or self.gradInput:max() > 10 then
        print 'Projection Gradient Exploding'
    end
    self.dnet = nil

    return self.gradInput
end

function Projection:__tostring__()
   return string.format('%s()', torch.type(self))
end
