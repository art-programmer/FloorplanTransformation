function [hC vC] = SpatialCues(im,sz)
im = im2double(im);
if(~exist('sz','var'))
    sz = 11;
end
g = fspecial('gauss', [sz sz], sqrt(sz));
dy = fspecial('sobel');
vf = conv2(g, dy, 'valid');
sz = size(im);
%vf = [1;-1];

vC = zeros(sz(1:2));
hC = vC;

for b=1:size(im,3)
    vC = max(vC, abs(imfilter(im(:,:,b), vf, 'symmetric')));
    hC = max(hC, abs(imfilter(im(:,:,b), vf', 'symmetric')));
end
end
