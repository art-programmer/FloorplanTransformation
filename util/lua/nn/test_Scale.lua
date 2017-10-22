require 'nn'
require 'Scale'

a = nn.Scale(100)
x = torch.rand(2, 3, 4, 4):mul(200/16)
y = torch.Tensor({{2, 2, 3, 3}, {1, 1, 3, 3}})

z = a:forward({x, y})
w = a:backward({x, y}, z)

print(x)
print(y)
print(z)
print(w)

