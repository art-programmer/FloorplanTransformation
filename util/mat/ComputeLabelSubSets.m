function  [subsets] = ComputeLabelSubSets(segIndexs,Labels)

subsets = cell(length(segIndexs),1);
for i = 1:length(segIndexs)
    imageNdxs = unique(segIndexs{i}.image);
    occMat = zeros(length(Labels{i}));
    for j = imageNdxs(:)'
        labelNdxs = unique(segIndexs{i}.label(segIndexs{i}.image==j));
        for k = labelNdxs(:)'
            occMat(k,labelNdxs) = occMat(k,labelNdxs)+1;
        end
    end
    distMeasure = occMat;
    distMeasure = distMeasure./repmat(sqrt(diag(distMeasure)),[1 size(distMeasure,2)])./repmat(sqrt(diag(distMeasure))',[size(distMeasure,2) 1]);
    distMeasure = 1-distMeasure;
    distMeasure = distMeasure - diag(diag(distMeasure));
    Z = linkage(squareform(distMeasure),'average');
    c = cluster(Z,'cutoff',.9,'criterion','distance');
    [foo lpsndx] = sort(c);lps = distMeasure(lpsndx,:);lps = lps(:,lpsndx);
    current = 0;
    for j = 1:max(c)
        clusterSize = sum(c==j);
        lps(current+1:current+clusterSize,current+1:current+clusterSize)=1;
        current = current+clusterSize;
    end
    clusterSplitMat = lps<.7;
    rowCount = sum(clusterSplitMat);
    while(any(rowCount>2))
        %show(clusterSplitMat);
        [rcMax ndx] = max(rowCount);
        c(lpsndx(ndx)) = max(c)+1;
        clusterSplitMat(ndx,:) = 0;
        clusterSplitMat(:,ndx) = 0;
        rowCount = sum(clusterSplitMat);
    end
    
    for j = 1:max(c)
        subsets{i}{j} = find(c==j);
    end
    fprintf('%d Clusters @ %.2f\n',max(c),.9);
    for j = 1:max(c)
        fprintf('%s ',Labels{i}{j==c});
        fprintf('\n');
    end
    fprintf('\n');
    %{
    %for experimentation
    fprintf('%s ',Labels{i}{:});
    fprintf('\n');
    cutoffs = .9;%.6:.1:
    for k = 1:length(cutoffs);
        c = cluster(Z,'cutoff',cutoffs(k),'criterion','distance');
        figure(k);dendrogram(Z,200,'colorthreshold',cutoffs(k));
        [foo ndx] = sort(c);lps = distMeasure(ndx,:);lps = lps(:,ndx);show(lps,k+length(cutoffs));
        fprintf('%d Clusters @ %.2f\n',max(c),cutoffs(k));
        for j = 1:max(c)
            fprintf('%s ',Labels{i}{j==c});
            fprintf('\n');
        end
        fprintf('\n');
    end
    fprintf('\n');
    %}
end

end