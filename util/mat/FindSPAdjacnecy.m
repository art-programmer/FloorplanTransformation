function [adjPairs] = FindSPAdjacnecy(imSP)
spndx = unique(imSP);
adjPairs = zeros(length(spndx)*(length(spndx)-1),2);
count = 1;
se = strel('square',3);
for i = spndx(:)'
    spMask = imSP==i;
    dSpMask = imdilate(spMask,se);
    dSpIm = imSP(dSpMask);
    spInds = unique(dSpIm);
    spInds = spInds(spInds~=i);
    spInds = intersect(spndx,spInds);
    for j=spInds(:)'
        adjPairs(count,:) = [i j];
        count = count+1;
    end
end
adjPairs(adjPairs(:,1)==0,:) = [];