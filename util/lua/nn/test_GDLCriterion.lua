require 'GDLCriterion'

a = torch.ones(2, 2, 2, 2)
b = torch.zeros(2, 2, 2, 2)

c = nn.GDLCriterion(2)
l = c:forward(a, b)
d = c:backward(a, b)
print(l)
print(d)

b[1][1][1][1] = 1
l = c:forward(a, b)
d = c:backward(a, b)
print(l)
print(d)

