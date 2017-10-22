require 'nn'
require 'Crop'

a = nn.Crop(8, 6, 4, 3)
x = torch.rand(1, 1, 6, 8)
y = torch.Tensor(1, 2, 2)
y[1][1][1] = 2
y[1][1][2] = 3
y[1][2][1] = 5
y[1][2][2] = 2

t = {}
t[1] = x
t[2] = y

z = a:forward(t)
w = a:backward(t, z)

print(x)
print(z)
print(w)

