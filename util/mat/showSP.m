function imMasked = showSP (im,imSP,spNum,crop,figNo)

if(~exist('crop','var'))
    crop = false;
end

[ro co ch] = size(im);
im = im2double(im);

if(crop)
    imMasked = ones(size(im));
else
    imMasked = ones(size(im));% im-.4;
end


mask = zeros(ro,co)==1;
maskl = zeros(ro,co);
for c = 1:ch
    temp = imMasked(:,:,c);
    tempIm = im(:,:,c);
    for sp = spNum(:)'
        temp(imSP==sp) = tempIm(imSP==sp);
        mask = mask|imSP==sp;
        maskl = maskl + (imdilate(imSP==sp, strel('disk',1))-(imSP==sp));
    end
    imMasked(:,:,c) = temp;
end
if(isempty(spNum))
    imMasked = im;
    spNums = unique(imSP);
    for sp = spNums(:)'
    	maskl = maskl + (imdilate(imSP==sp, strel('disk',1))-(imSP==sp));
    end
end

if(crop)
    [y x] = find(mask);
    temp = imMasked;
    imMasked = [];
    for c = 1:ch
        imMasked(:,:,c) = temp(min(y):max(y),min(x):max(x),c);
    end
    mask = mask(min(y):max(y),min(x):max(x));
    maskl = maskl(min(y):max(y),min(x):max(x));
end


%maskd = imdilate(mask, strel('disk',1));
%maskl = maskd-mask;
for c = 1:ch
    if(~crop)
        temp = im(:,:,c);
        temp(~mask) = temp(~mask);
        imMasked(:,:,c) = temp;
    end
    temp = imMasked(:,:,c);
    temp(maskl~=0) = 1.0*(c==2);
    imMasked(:,:,c) = temp;
end



if(exist('figNo','var'))
    show(imMasked,figNo);
else
    show(imMasked);
    figNo = 0;
end
%make_dir('D:\tempsp\bl.jpg');
%if(~isempty(imMasked))
%    imwrite(imMasked,fullfile('D:\tempsp',sprintf('%d.png',figNo)));
%end


