require 'CrossConvolve'

t = nn.CrossConvolve(1,3)

a = torch.rand(2,1,3,3)
a[1][1] = torch.eye(3)
a[2][1] = torch.eye(3)
b = torch.eye(3)
c = t:forward({a,b})

d = torch.rand(2,1,3,3)
d[1][1] = torch.eye(3)
d[2][1] = torch.eye(3)
e = t:backward({a,b},d)
