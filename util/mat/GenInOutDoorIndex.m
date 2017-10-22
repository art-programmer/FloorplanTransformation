%{-
trainInOutIndex = zeros(size(trainFileList));

for i = 1:length(trainFileList)
    [fold name] = fileparts(trainFileList{i});
    clear metaData;
    load(fullfile(HOMELABELSETS{2},fold,[name '.mat'])); %S names metadata
    trainInOutIndex(i) = metaData.inOutDoor;
end

testInOutIndex = zeros(size(testFileList));

for i = 1:length(testFileList)
    [fold name] = fileparts(testFileList{i});
    clear metaData;
    load(fullfile(HOMELABELSETS{2},fold,[name '.mat'])); %S names metadata
    testInOutIndex(i) = metaData.inOutDoor;
end

indoorMask = zeros(size(trainIndex{2}.sp))==1;
outdoorMask = zeros(size(trainIndex{2}.sp))==1;
for i = 1:length(trainFileList);
    if(trainInOutIndex(i) == 1)
        indoorMask(trainIndex{2}.image==i) = 1;
    end
    if(trainInOutIndex(i) == 2)
        outdoorMask(trainIndex{2}.image==i) = 1;
    end
end

%}

indoorMaskTest = zeros(size(testIndex{2}.sp))==1;
outdoorMaskTest = zeros(size(testIndex{2}.sp))==1;
for i = 1:length(testFileList);
    if(testInOutIndex(i) == 1)
        indoorMaskTest(testIndex{2}.image==i) = 1;
    end
    if(testInOutIndex(i) == 2)
        outdoorMaskTest(testIndex{2}.image==i) = 1;
    end
end