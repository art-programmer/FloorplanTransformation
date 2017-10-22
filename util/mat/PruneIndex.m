function [index mask] = PruneIndex(index, imageNNs, minImages, minSegments)
if(~exist('minImages','var'))
    minImages=length(imageNNs);
end
if(~exist('minSegments','var'))
    minSegments=0;
end
minImages = min(minImages,length(imageNNs));
mask = zeros(size(index.image))==1;
for i = 1:minImages
    mask(index.image==imageNNs(i)) = 1;
end
while(sum(mask)<minSegments)
    i = i+1;
    if(i>length(imageNNs))
        break;
    end
    mask = mask | index.image==imageNNs(i);
end
    
names = fieldnames(index);
for i = 1:length(names)
    index.(names{i}) = index.(names{i})(mask);
end