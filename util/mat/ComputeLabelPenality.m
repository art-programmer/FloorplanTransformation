function  [interLabPenality occMat] = ComputeLabelPenality(fileList,HOMEDATA,segDir,segIndexs,testSetName,Labels)
pfig = ProgressBar('Compute Label Penality');
HOMEDESCDATA = fullfile(HOMEDATA,'Descriptors',segDir);
occFile = fullfile(HOMEDATA,'Descriptors',segDir,sprintf('CoOccurance%s.mat',testSetName));
occMat = cell(length(segIndexs));
occMatGood = 0;
if(exist(occFile,'file'))
    load(occFile);
    if(size(occMat,1) == length(segIndexs) && size(occMat,2) == length(segIndexs))
        for i = 1:length(segIndexs)
            if(size(occMat{i,i},1) == length(Labels{i}) && size(occMat{i,i},2) == length(Labels{i}))
                occMatGood = occMatGood + 1;
            end
        end
    end
end
if(occMatGood<length(segIndexs))
    occMat = cell(length(segIndexs));
    for i = 1:length(segIndexs)
        occMat{i,i} = zeros(length(Labels{i}));
    end
    for j = 1:length(fileList)
        [folder file] = fileparts(fileList{j});
        adjFile = fullfile(HOMEDESCDATA,'sp_adjacency',folder,[file '.mat']);
        load(adjFile);

        for i = 1:length(segIndexs)
            labelMap = zeros(max(adjPairs(:)),1);
            spNdx = segIndexs{i}.sp(segIndexs{i}.image==j);
            labelMap(spNdx) = segIndexs{i}.label(segIndexs{i}.image==j);
            adjLabels = labelMap(adjPairs);
            [y,x] = find(adjLabels==0);
            adjLabels(y,:) = [];
            inds = sub2ind(size(occMat{i,i}),adjLabels(:,1),adjLabels(:,2));
            [inds addamt] = UniqueAndCounts(inds);
            occMat{i,i}(inds) = occMat{i,i}(inds)+addamt;
        end
        if(mod(j,100)==0)
            ProgressBar(pfig,j,length(fileList));
        end
    end
    save(occFile,'occMat');
end
tic

occMatGood = 0;
occTotal = length(segIndexs)*(length(segIndexs)-1)/2;
if(size(occMat,1) == length(segIndexs) && size(occMat,2) == length(segIndexs))
    for j = 1:length(segIndexs)
        for k = j+1:length(segIndexs)
            if(size(occMat{j,k},1) == length(Labels{j}) && size(occMat{j,k},2) == length(Labels{k}))
                occMatGood = occMatGood + 1;
            end
        end
    end
end
if(occTotal~=occMatGood)
    for j = 1:length(segIndexs)
        for k = j+1:length(segIndexs)
            occMat{j,k} = zeros(length(Labels{j}),length(Labels{k}));
        end
    end
    for i = 1:length(fileList)
        for j = 1:length(segIndexs)
            for k = (j+1):length(segIndexs)
            	spNdxj = segIndexs{j}.sp(segIndexs{j}.image==i);
            	spNdxk = segIndexs{k}.sp(segIndexs{k}.image==i);
                [spNdx jind kind] = intersect(spNdxj,spNdxk);
                jl = segIndexs{j}.label(segIndexs{j}.image==i);jl=jl(:);
                kl = segIndexs{k}.label(segIndexs{k}.image==i);kl=kl(:);
                adjLabels = [jl(jind(:)) kl(kind(:))];
                inds = sub2ind(size(occMat{j,k}),adjLabels(:,1),adjLabels(:,2));
                [inds addamt] = UniqueAndCounts(inds);
                occMat{j,k}(inds) = occMat{j,k}(inds)+addamt;
            end
        end
        if(mod(i,100)==0)
            ProgressBar(pfig,i,length(fileList));
        end
    end
    for j = 1:length(segIndexs)
        for k = (j+1):length(segIndexs)
            occMat{k,j} = occMat{j,k}';
        end
    end
    save(occFile,'occMat');
end
close(pfig);

interLabPenality = cell(size(occMat));
for j = 1:length(segIndexs)
    for k = j:length(segIndexs)
        occ = occMat{j,k};
        occ = occ+.1;
        lpc = sum(occ);
        condiProb1 = occ./repmat(lpc,[size(occ,1) 1]);
        lpc = sum(occ,2);
        condiProb2 = occ./repmat(lpc,[1 size(occ,2)]);
        condiProb=-log((condiProb1+condiProb2)./2);
        if(j==k)
            condiProb = condiProb - diag(diag(condiProb));
        end
        fprintf('%d %d: %.3f\n',j,k,max(condiProb(:)));
        condiProb = condiProb./max(condiProb(:));
        interLabPenality{j,k} = condiProb;
        if(j~=k)
            interLabPenality{k,j} = condiProb';
        end
    end
end
