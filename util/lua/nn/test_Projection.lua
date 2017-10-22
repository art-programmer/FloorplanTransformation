require 'torch'
require 'nn'
require 'Projection'

num_params = 14
min_param_values = {30, -70, -70, -15, 0, 1/450, -1, -1, -1, -1, -1, -1, -60, -80}
max_param_values = {50, 100, 100, 100, 150, 1/120, 1, 1, 1, 1, 1, 1, 60, 80}
weight_params = torch.ones(num_params)
weight_params[6] = 10
batch_size = 3

x = torch.load('/data/vision/billf/jwu-recog/pose/data/chair/data/outputs_latent_test_001.torch')
x = x[{{1, batch_size}}]
   
Bs = torch.Tensor({{{-1,-2,1},{1,-2,1},{1,-2,-1},{-1,-2,-1},{-1,0,1},{1,0,1},{1,0,-1},{-1,0,-1},{-1,2,-1},{1,2,-1}},
                   {{0,-1,0},{0,-1,0},{0,-1,0},{0,-1,0},{0,0,0},{0,0,0},{0,0,0},{0,0,0},{0,0,0},{0,0,0}},
                   {{0,0,0},{0,0,0},{0,0,0},{0,0,0},{0,0,0},{0,0,0},{0,0,0},{0,0,0},{0,1,0},{0,1,0}},
                   {{-1,0,0},{1,0,0},{1,0,0},{-1,0,0},{-1,0,0},{1,0,0},{1,0,0},{-1,0,0},{-1,0,0},{1,0,0}},
                   {{-1,0,1},{1,0,1},{1,0,-1},{-1,0,-1},{0,0,0},{0,0,0},{0,0,0},{0,0,0},{0,0,0},{0,0,0}}}):permute(1, 3, 2)

a = nn.Projection(Bs, min_param_values, max_param_values, weight_params, 5)
print('x')
print(x)
y = a:forward(x)
print('y')
print(y)

z = a:backward(x, torch.ones(batch_size, 10, 2))
print('z')
print(z)

