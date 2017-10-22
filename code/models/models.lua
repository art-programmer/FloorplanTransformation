require 'nngraph'

function defineG_encoder_decoder(input_nc, output_nc, ngf)
    
    -- input is (nc) x 256 x 256
    e1 = - nn.SpatialConvolution(input_nc, ngf, 4, 4, 2, 2, 1, 1)
    -- input is (ngf) x 128 x 128
    e2 = e1 - nn.LeakyReLU(0.2, true) - nn.SpatialConvolution(ngf, ngf * 2, 4, 4, 2, 2, 1, 1) - nn.SpatialBatchNormalization(ngf * 2)
    -- input is (ngf * 2) x 64 x 64
    e3 = e2 - nn.LeakyReLU(0.2, true) - nn.SpatialConvolution(ngf * 2, ngf * 4, 4, 4, 2, 2, 1, 1) - nn.SpatialBatchNormalization(ngf * 4)
    -- input is (ngf * 4) x 32 x 32
    e4 = e3 - nn.LeakyReLU(0.2, true) - nn.SpatialConvolution(ngf * 4, ngf * 8, 4, 4, 2, 2, 1, 1) - nn.SpatialBatchNormalization(ngf * 8)
    -- input is (ngf * 8) x 16 x 16
    e5 = e4 - nn.LeakyReLU(0.2, true) - nn.SpatialConvolution(ngf * 8, ngf * 8, 4, 4, 2, 2, 1, 1) - nn.SpatialBatchNormalization(ngf * 8)
    -- input is (ngf * 8) x 8 x 8
    e6 = e5 - nn.LeakyReLU(0.2, true) - nn.SpatialConvolution(ngf * 8, ngf * 8, 4, 4, 2, 2, 1, 1) - nn.SpatialBatchNormalization(ngf * 8)
    -- input is (ngf * 8) x 4 x 4
    e7 = e6 - nn.LeakyReLU(0.2, true) - nn.SpatialConvolution(ngf * 8, ngf * 8, 4, 4, 2, 2, 1, 1) - nn.SpatialBatchNormalization(ngf * 8)
    -- input is (ngf * 8) x 2 x 2
    e8 = e7 - nn.LeakyReLU(0.2, true) - nn.SpatialConvolution(ngf * 8, ngf * 8, 4, 4, 2, 2, 1, 1) - nn.SpatialBatchNormalization(ngf * 8)
    -- input is (ngf * 8) x 1 x 1
    
    d1 = e8 - nn.ReLU(true) - nn.SpatialFullConvolution(ngf * 8, ngf * 8, 4, 4, 2, 2, 1, 1) - nn.SpatialBatchNormalization(ngf * 8) - nn.Dropout(0.5)    
    -- input is (ngf * 8) x 2 x 2    
    d2 = d1 - nn.ReLU(true) - nn.SpatialFullConvolution(ngf * 8, ngf * 8, 4, 4, 2, 2, 1, 1) - nn.SpatialBatchNormalization(ngf * 8) - nn.Dropout(0.5)    
    -- input is (ngf * 8) x 4 x 4    
    d3 = d2 - nn.ReLU(true) - nn.SpatialFullConvolution(ngf * 8, ngf * 8, 4, 4, 2, 2, 1, 1) - nn.SpatialBatchNormalization(ngf * 8) - nn.Dropout(0.5)    
    -- input is (ngf * 8) x 8 x 8    
    d4 = d3 - nn.ReLU(true) - nn.SpatialFullConvolution(ngf * 8, ngf * 8, 4, 4, 2, 2, 1, 1) - nn.SpatialBatchNormalization(ngf * 8)    
    -- input is (ngf * 8) x 16 x 16    
    d5 = d4 - nn.ReLU(true) - nn.SpatialFullConvolution(ngf * 8, ngf * 4, 4, 4, 2, 2, 1, 1) - nn.SpatialBatchNormalization(ngf * 4)    
    -- input is (ngf * 4) x 32 x 32    
    d6 = d5 - nn.ReLU(true) - nn.SpatialFullConvolution(ngf * 4, ngf * 2, 4, 4, 2, 2, 1, 1) - nn.SpatialBatchNormalization(ngf * 2)    
    -- input is (ngf * 2) x 64 x 64    
    d7 = d6 - nn.ReLU(true) - nn.SpatialFullConvolution(ngf * 2, ngf, 4, 4, 2, 2, 1, 1) - nn.SpatialBatchNormalization(ngf)    
    -- input is (ngf) x128 x 128    
    d8 = d7 - nn.ReLU(true) - nn.SpatialFullConvolution(ngf * 2, output_nc, 4, 4, 2, 2, 1, 1)    
    -- input is (nc) x 256 x 256    
    
    o1 = d8 - nn.Tanh()
    
    netG = nn.gModule({e1},{o1})
    
    --graph.dot(netG.fg,'netG')
    
    return netG
end


function defineG_unet(input_nc, output_nc, ngf)
   
   -- input is (nc) x 256 x 256
   local netG = nn.Sequential()

   local skipLayer_1 = nn.Sequential()
   skipLayer_1:add(nn.SpatialConvolution(input_nc, ngf, 4, 4, 2, 2, 1, 1))
   
   local skipLayer_2 = nn.Sequential()   
   skipLayer_2:add(nn.LeakyReLU(0.2, true)):add(nn.SpatialConvolution(ngf, ngf * 2, 4, 4, 2, 2, 1, 1)):add(nn.SpatialBatchNormalization(ngf * 2))

   local skipLayer_3 = nn.Sequential()
   skipLayer_3:add(nn.LeakyReLU(0.2, true)):add(nn.SpatialConvolution(ngf * 2, ngf * 4, 4, 4, 2, 2, 1, 1)):add(nn.SpatialBatchNormalization(ngf * 4))

   local skipLayer_4 = nn.Sequential()
   skipLayer_4:add(nn.LeakyReLU(0.2, true)):add(nn.SpatialConvolution(ngf * 4, ngf * 8, 4, 4, 2, 2, 1, 1)):add(nn.SpatialBatchNormalization(ngf * 8))

   local skipLayer_5 = nn.Sequential()   
   skipLayer_5:add(nn.LeakyReLU(0.2, true)):add(nn.SpatialConvolution(ngf * 8, ngf * 8, 4, 4, 2, 2, 1, 1)):add(nn.SpatialBatchNormalization(ngf * 8))   

   local skipLayer_6 = nn.Sequential()   
   skipLayer_6:add(nn.LeakyReLU(0.2, true)):add(nn.SpatialConvolution(ngf * 8, ngf * 8, 4, 4, 2, 2, 1, 1)):add(nn.SpatialBatchNormalization(ngf * 8))

   local skipLayer_7 = nn.Sequential()
   skipLayer_7:add(nn.LeakyReLU(0.2, true)):add(nn.SpatialConvolution(ngf * 8, ngf * 8, 4, 4, 2, 2, 1, 1)):add(nn.SpatialBatchNormalization(ngf * 8))

   local skipLayer_8 = nn.Sequential()
   skipLayer_8:add(nn.LeakyReLU(0.2, true)):add(nn.SpatialConvolution(ngf * 8, ngf * 8, 4, 4, 2, 2, 1, 1)):add(nn.SpatialBatchNormalization(ngf * 8))
   
   skipLayer_8:add(nn.ReLU(true)):add(nn.SpatialFullConvolution(ngf * 8, ngf * 8, 4, 4, 2, 2, 1, 1)):add(nn.SpatialBatchNormalization(ngf * 8)):add(nn.Dropout(0.5))
   
   skipLayer_7:add(nn.ConcatTable():add(skipLayer_8):add(nn.Identity()))            
   skipLayer_7:add(nn.JoinTable(1, 3))
   skipLayer_7:add(nn.ReLU(true)):add(nn.SpatialFullConvolution(ngf * 8 * 2, ngf * 8, 4, 4, 2, 2, 1, 1)):add(nn.SpatialBatchNormalization(ngf * 8)):add(nn.Dropout(0.5))
   
   skipLayer_6:add(nn.ConcatTable():add(skipLayer_7):add(nn.Identity()))            
   skipLayer_6:add(nn.JoinTable(1, 3))
   skipLayer_6:add(nn.ReLU(true)):add(nn.SpatialFullConvolution(ngf * 8 * 2, ngf * 8, 4, 4, 2, 2, 1, 1)):add(nn.SpatialBatchNormalization(ngf * 8)):add(nn.Dropout(0.5))
   
   skipLayer_5:add(nn.ConcatTable():add(skipLayer_6):add(nn.Identity()))         
   skipLayer_5:add(nn.JoinTable(1, 3))
   skipLayer_5:add(nn.ReLU(true)):add(nn.SpatialFullConvolution(ngf * 8 * 2, ngf * 8, 4, 4, 2, 2, 1, 1)):add(nn.SpatialBatchNormalization(ngf * 8))
   
   skipLayer_4:add(nn.ConcatTable():add(skipLayer_5):add(nn.Identity()))
   skipLayer_4:add(nn.JoinTable(1, 3))
   skipLayer_4:add(nn.ReLU(true)):add(nn.SpatialFullConvolution(ngf * 8 * 2, ngf * 4, 4, 4, 2, 2, 1, 1)):add(nn.SpatialBatchNormalization(ngf * 4))
   
   skipLayer_3:add(nn.ConcatTable():add(skipLayer_4):add(nn.Identity()))   
   skipLayer_3:add(nn.JoinTable(1, 3))
   skipLayer_3:add(nn.ReLU(true)):add(nn.SpatialFullConvolution(ngf * 4 * 2, ngf * 2, 4, 4, 2, 2, 1, 1)):add(nn.SpatialBatchNormalization(ngf * 2))
   
   skipLayer_2:add(nn.ConcatTable():add(skipLayer_3):add(nn.Identity()))
   skipLayer_2:add(nn.JoinTable(1, 3))
   skipLayer_2:add(nn.ReLU(true)):add(nn.SpatialFullConvolution(ngf * 2 * 2, ngf, 4, 4, 2, 2, 1, 1)):add(nn.SpatialBatchNormalization(ngf))
   
   skipLayer_1:add(nn.ConcatTable():add(skipLayer_2):add(nn.Identity()))
   skipLayer_1:add(nn.JoinTable(1, 3))
   skipLayer_1:add(nn.ReLU(true)):add(nn.SpatialFullConvolution(ngf * 2, output_nc, 4, 4, 2, 2, 1, 1))
   
   netG:add(skipLayer_1)
   netG:add(nn.Tanh())
   
   return netG
end

function defineG_unet_iter(input_nc, output_nc, ngf, activation)
   
   -- input is (nc) x 256 x 256
   local netG = nn.Sequential()

   local skipLayers = {}
   for i = 1, 8 do
      skipLayers[i] = nn.Sequential()
      if i == 1 then
	 skipLayers[i]:add(nn.SpatialConvolution(input_nc, ngf, 4, 4, 2, 2, 1, 1))
      else
	 skipLayers[i]:add(nn.LeakyReLU(0.2, true)):add(nn.SpatialConvolution(ngf * 2^math.min(i - 2, 3), ngf * 2^math.min(i - 1, 3), 4, 4, 2, 2, 1, 1)):add(nn.SpatialBatchNormalization(ngf * 2^math.min(i - 1, 3)))
      end
   end

   skipLayers[8]:add(nn.ReLU(true)):add(nn.SpatialFullConvolution(ngf * 8, ngf * 8, 4, 4, 2, 2, 1, 1)):add(nn.SpatialBatchNormalization(ngf * 8)):add(nn.Dropout(0.5))
   
   for i = 7, 1, -1 do
      skipLayers[i]:add(nn.ConcatTable():add(skipLayers[i + 1]):add(nn.Identity()))
      skipLayers[i]:add(nn.JoinTable(1, 3))
      --skipLayers[i]:add(nn.ReLU(true)):add(nn.SpatialFullConvolution(ngf * 8 * 2, ngf * 8, 4, 4, 2, 2, 1, 1)):add(nn.SpatialBatchNormalization(ngf * 8)):add(nn.Dropout(0.5))
      if i > 1 then
	 skipLayers[i]:add(nn.ReLU(true)):add(nn.SpatialFullConvolution(ngf * 2^math.min(i - 1, 3) * 2, ngf * 2^math.min(i - 2, 3), 4, 4, 2, 2, 1, 1)):add(nn.SpatialBatchNormalization(ngf * 2^math.min(i - 2, 3)))
	 if i >= 6 then      
            skipLayers[i]:add(nn.Dropout(0.5))      
         end
      else
	 skipLayers[i]:add(nn.ReLU(true)):add(nn.SpatialFullConvolution(ngf * 2, output_nc, 4, 4, 2, 2, 1, 1))
      end
   end
   
   netG:add(skipLayers[1])
   if activation then
      netG:add(activation)
   end
   
   return netG
end

function defineG_unet_nngraph(input_nc, output_nc, ngf)
    
    -- input is (nc) x 256 x 256
    e1 = - nn.SpatialConvolution(input_nc, ngf, 4, 4, 2, 2, 1, 1)
    -- input is (ngf) x 128 x 128
    e2 = e1 - nn.LeakyReLU(0.2, true) - nn.SpatialConvolution(ngf, ngf * 2, 4, 4, 2, 2, 1, 1) - nn.SpatialBatchNormalization(ngf * 2)
    -- input is (ngf * 2) x 64 x 64
    e3 = e2 - nn.LeakyReLU(0.2, true) - nn.SpatialConvolution(ngf * 2, ngf * 4, 4, 4, 2, 2, 1, 1) - nn.SpatialBatchNormalization(ngf * 4)
    -- input is (ngf * 4) x 32 x 32
    e4 = e3 - nn.LeakyReLU(0.2, true) - nn.SpatialConvolution(ngf * 4, ngf * 8, 4, 4, 2, 2, 1, 1) - nn.SpatialBatchNormalization(ngf * 8)
    -- input is (ngf * 8) x 16 x 16
    e5 = e4 - nn.LeakyReLU(0.2, true) - nn.SpatialConvolution(ngf * 8, ngf * 8, 4, 4, 2, 2, 1, 1) - nn.SpatialBatchNormalization(ngf * 8)
    -- input is (ngf * 8) x 8 x 8
    e6 = e5 - nn.LeakyReLU(0.2, true) - nn.SpatialConvolution(ngf * 8, ngf * 8, 4, 4, 2, 2, 1, 1) - nn.SpatialBatchNormalization(ngf * 8)
    -- input is (ngf * 8) x 4 x 4
    e7 = e6 - nn.LeakyReLU(0.2, true) - nn.SpatialConvolution(ngf * 8, ngf * 8, 4, 4, 2, 2, 1, 1) - nn.SpatialBatchNormalization(ngf * 8)
    -- input is (ngf * 8) x 2 x 2
    e8 = e7 - nn.LeakyReLU(0.2, true) - nn.SpatialConvolution(ngf * 8, ngf * 8, 4, 4, 2, 2, 1, 1) - nn.SpatialBatchNormalization(ngf * 8)
    -- input is (ngf * 8) x 1 x 1
    
    d1_ = e8 - nn.ReLU(true) - nn.SpatialFullConvolution(ngf * 8, ngf * 8, 4, 4, 2, 2, 1, 1) - nn.SpatialBatchNormalization(ngf * 8) - nn.Dropout(0.5)
    -- input is (ngf * 8) x 2 x 2
    d1 = {d1_,e7} - nn.JoinTable(2)
    d2_ = d1 - nn.ReLU(true) - nn.SpatialFullConvolution(ngf * 8 * 2, ngf * 8, 4, 4, 2, 2, 1, 1) - nn.SpatialBatchNormalization(ngf * 8) - nn.Dropout(0.5)
    -- input is (ngf * 8) x 4 x 4
    d2 = {d2_,e6} - nn.JoinTable(2)
    d3_ = d2 - nn.ReLU(true) - nn.SpatialFullConvolution(ngf * 8 * 2, ngf * 8, 4, 4, 2, 2, 1, 1) - nn.SpatialBatchNormalization(ngf * 8) - nn.Dropout(0.5)
    -- input is (ngf * 8) x 8 x 8
    d3 = {d3_,e5} - nn.JoinTable(2)
    d4_ = d3 - nn.ReLU(true) - nn.SpatialFullConvolution(ngf * 8 * 2, ngf * 8, 4, 4, 2, 2, 1, 1) - nn.SpatialBatchNormalization(ngf * 8)
    -- input is (ngf * 8) x 16 x 16
    d4 = {d4_,e4} - nn.JoinTable(2)
    d5_ = d4 - nn.ReLU(true) - nn.SpatialFullConvolution(ngf * 8 * 2, ngf * 4, 4, 4, 2, 2, 1, 1) - nn.SpatialBatchNormalization(ngf * 4)
    -- input is (ngf * 4) x 32 x 32
    d5 = {d5_,e3} - nn.JoinTable(2)
    d6_ = d5 - nn.ReLU(true) - nn.SpatialFullConvolution(ngf * 4 * 2, ngf * 2, 4, 4, 2, 2, 1, 1) - nn.SpatialBatchNormalization(ngf * 2)
    -- input is (ngf * 2) x 64 x 64
    d6 = {d6_,e2} - nn.JoinTable(2)
    d7_ = d6 - nn.ReLU(true) - nn.SpatialFullConvolution(ngf * 2 * 2, ngf, 4, 4, 2, 2, 1, 1) - nn.SpatialBatchNormalization(ngf)
    -- input is (ngf) x128 x 128
    d7 = {d7_,e1} - nn.JoinTable(2)
    d8 = d7 - nn.ReLU(true) - nn.SpatialFullConvolution(ngf * 2, output_nc, 4, 4, 2, 2, 1, 1)
    -- input is (nc) x 256 x 256
    
    o1 = d8 - nn.Tanh()
    
    netG = nn.gModule({e1},{o1})
    
    --graph.dot(netG.fg,'netG')
    
    return netG
end

function defineD_basic(input_nc, output_nc, ndf)
    
    n_layers = 3
    return defineD_n_layers(input_nc, output_nc, ndf, n_layers)
end

-- rf=1
function defineD_pixelGAN(input_nc, output_nc, ndf)
    
    local netD = nn.Sequential()
    
    -- input is (nc) x 256 x 256
    netD:add(nn.SpatialConvolution(input_nc+output_nc, ndf, 1, 1, 1, 1, 0, 0))
    netD:add(nn.LeakyReLU(0.2, true))
    -- state size: (ndf) x 256 x 256
    netD:add(nn.SpatialConvolution(ndf, ndf * 2, 1, 1, 1, 1, 0, 0))
    netD:add(nn.SpatialBatchNormalization(ndf * 2)):add(nn.LeakyReLU(0.2, true))
    -- state size: (ndf*2) x 256 x 256
    netD:add(nn.SpatialConvolution(ndf * 2, 1, 1, 1, 1, 1, 0, 0))
    -- state size: 1 x 256 x 256
    
    netD:add(nn.Sigmoid())
    -- state size: 1 x 30 x 30
        
    return netD
end

-- if n=0, then use pixelGAN (rf=1)
-- else rf is 16 if n=1
--            34 if n=2
--            70 if n=3
--            142 if n=4
--            286 if n=5
--            574 if n=6
function defineD_n_layers(input_nc, output_nc, ndf, n_layers)
    
    if n_layers==0 then
        return defineD_pixelGAN(input_nc, output_nc, ndf)
    else
    
        local netD = nn.Sequential()
        
        -- input is (nc) x 256 x 256
        netD:add(nn.SpatialConvolution(input_nc+output_nc, ndf, 4, 4, 2, 2, 1, 1))
        netD:add(nn.LeakyReLU(0.2, true))
        
        nf_mult = 1
        for n = 1, n_layers-1 do 
            nf_mult_prev = nf_mult
            nf_mult = math.min(2^n,8)
            netD:add(nn.SpatialConvolution(ndf * nf_mult_prev, ndf * nf_mult, 4, 4, 2, 2, 1, 1))
            netD:add(nn.SpatialBatchNormalization(ndf * nf_mult)):add(nn.LeakyReLU(0.2, true))
        end
        
        -- state size: (ndf*M) x N x N
        nf_mult_prev = nf_mult
        nf_mult = math.min(2^n_layers,8)
        netD:add(nn.SpatialConvolution(ndf * nf_mult_prev, ndf * nf_mult, 4, 4, 1, 1, 1, 1))
        netD:add(nn.SpatialBatchNormalization(ndf * nf_mult)):add(nn.LeakyReLU(0.2, true))
        -- state size: (ndf*M*2) x (N-1) x (N-1)
        --netD:add(nn.SpatialConvolution(ndf * nf_mult, 1, 4, 4, 1, 1, 1, 1))
        -- state size: 1 x (N-2) x (N-2)
        
        --netD:add(nn.Sigmoid())
        -- state size: 1 x (N-2) x (N-2)
        netD:add(nn.SpatialConvolution(ndf * nf_mult, 2, 1, 1))
        return netD
    end
end
