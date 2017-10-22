function [skelSP relweight] = SPtoSkel(imSP)

spNdx = unique(imSP);
skelSP = zeros(size(imSP));
relweight = zeros(max(spNdx),1);
%se = strel('disk',5);
for i = spNdx(:)'
    mask = imSP == i;
    relweight(i) = sum(mask(:));
    %show(mask,1);
    mask = bwmorph(mask,'skel',Inf);
    %mask = imerode(mask,se);
    relweight(i) = relweight(i)/sum(mask(:));
    %show(mask,2);
    skelSP(mask) = i;
end

relweight = relweight./mean(relweight);
