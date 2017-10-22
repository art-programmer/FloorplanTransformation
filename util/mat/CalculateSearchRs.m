function [searchRs] = CalculateSearchRs(trainFileList,HOMEDATA,trainIndex,descFuns,K,segSuffix)

outfilename = fullfile(HOMEDATA,sprintf('SPsearchRs_k%d%s.mat',K,segSuffix));
if(exist(outfilename,'file'))
    load(outfilename);
    %return;
else
    searchRs = [];
end

numNNs = [20:20:200];
randInd = [];
numRand = 1000;
dists = zeros(numRand,length(numNNs));

contCount = 0;
for i = 1:length(descFuns)
    if(isfield(searchRs,descFuns{i}))
        contCount = contCount +1;
        continue;
    end
    if(~exist('retSetSPDesc','var'))
        imInd = randperm(length(trainFileList));
        retSetIndex = PruneIndex(trainIndex,imInd,min(length(imInd),2000),0);
        retSetSPDesc = LoadSegmentDesc(trainFileList,retSetIndex,HOMEDATA,descFuns,K,segSuffix);
    end
    
    data = retSetSPDesc.(descFuns{i});
    numRand = min(numRand,size(data,1));
    if(isempty(randInd))
        randInd = randperm(size(data,1));
        randInd = randInd(1:numRand);
    end
    for j = 1:numRand
        query = data(randInd(j),:);
        tic
        dist = sqrt(dist2(query,data));
        fprintf('%d-%d: %.2f\n',i,j,toc);
        dist = sort(dist);
        for k = 1:length(numNNs)
            dists(j,k) = dist(numNNs(k));
        end
    end
    Rs = median(dists);
    searchRs.(descFuns{i}).Rs = Rs;
    searchRs.(descFuns{i}).numNNs = numNNs;
    
    fprintf('%s std: %.5f dim: %d\n',descFuns{i},Rs(1),size(data,1));
end
if(contCount<length(descFuns))
    save(outfilename,'searchRs');
end
