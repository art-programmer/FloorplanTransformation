
fileList = dir_recurse(fullfile(HOMEIMAGES,'*.*'),0);
labelSetNumForCoverage = 2;
labelCoverage = [];
coverageFile = fullfile(HOME,'labelCoverage.mat');
if(exist(coverageFile,'file'))
    load(coverageFile);
end
if(length(labelCoverage)~=length(fileList))
    labelCoverage = zeros(size(fileList));
    pfig = ProgressBar('Computing Label Coverage');
    for i = 1:length(fileList)
        [fold file ext] = fileparts(fileList{i});
        loadFile = fullfile(HOMELABELSETS{labelSetNumForCoverage},fold,[file '.mat']);
        load(loadFile);
        labelCoverage(i) = 1-(sum(S(:)==0)/numel(S));
        ProgressBar(pfig,i,length(fileList));
    end
    close(pfig);
    save(coverageFile,'labelCoverage');
end

coverageThresh = .9;
testSetSize = 300;
maxTestSets = 5;

testCandidates = find(labelCoverage>coverageThresh);
testCandidates = testCandidates(randperm(length(testCandidates)));

testSet = 1;
while(testSet<=maxTestSets)
    if(length(testCandidates)< testSetSize)
        break;
    end
    testSetNdx = sort(testCandidates(1:testSetSize));testCandidates(1:testSetSize)=[];
    fid = fopen(fullfile(HOME,['TestSet' num2str(testSet) '.txt']),'w');
    for i = testSetNdx(:)'
        fprintf(fid,'%s\n',fileList{i});
    end
    fclose(fid);
    testSet = testSet + 1;
end