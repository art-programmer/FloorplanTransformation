require 'torch'
grad = require 'autograd'

function net(params, x)
    local p = params[1][2]
    local q = params[1][3]
    return p + 2 * q
end


dnet = grad(net)
params = torch.Tensor({{2, 3, 3}})
dparams = dnet(params, x)
